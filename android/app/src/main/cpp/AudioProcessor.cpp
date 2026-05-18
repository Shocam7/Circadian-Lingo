// AudioProcessor.cpp — JNI entry point: WAD I/O + Silero VAD silence stripping
//
// Called from Kotlin on Dispatchers.IO. Never call from the main thread.
#include "AudioProcessor.h"
#include "VadBridge.h"

#include <fstream>
#include <sstream>
#include <cstring>
#include <ctime>

// ─────────────────────────────────────────────────────────────────────────────
// WAV I/O helpers
// ─────────────────────────────────────────────────────────────────────────────

// Minimal WAV header (44 bytes, PCM format).
#pragma pack(push, 1)
struct WavHdr {
    char     riff[4];        char     wave[4];
    char     fmt_[4];        uint32_t subchunk1Size;
    uint16_t audioFormat;    uint16_t numChannels;
    uint32_t sampleRate;     uint32_t byteRate;
    uint16_t blockAlign;     uint16_t bitsPerSample;
    char     data[4];        uint32_t dataSize;
    char     riffId[4];      uint32_t chunkSize; // reordered for real layout below
};
#pragma pack(pop)

// Real RIFF layout — define as simple struct.
struct RiffWav {
    char     riff[4];       uint32_t chunkSize;
    char     wave[4];       char     fmt_[4];
    uint32_t subchunk1Sz;   uint16_t audioFmt;
    uint16_t channels;      uint32_t sampleRate;
    uint32_t byteRate;      uint16_t blockAlign;
    uint16_t bitsPerSample; char     data[4];
    uint32_t dataSize;
};

size_t readPcmWav(const std::string& path, std::vector<int16_t>& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) { AP_LOGE("Cannot open WAV: %s", path.c_str()); return 0; }

    RiffWav hdr{};
    f.read(reinterpret_cast<char*>(&hdr), sizeof(hdr));
    if (!f || strncmp(hdr.riff, "RIFF", 4) != 0) {
        AP_LOGE("Not a RIFF file: %s", path.c_str());
        return 0;
    }
    if (hdr.audioFmt != 1 || hdr.bitsPerSample != 16 || hdr.channels != 1) {
        AP_LOGE("Expected 16-bit mono PCM, got fmt=%d bits=%d ch=%d",
                hdr.audioFmt, hdr.bitsPerSample, hdr.channels);
        return 0;
    }

    const size_t numSamples = hdr.dataSize / 2;
    out.resize(numSamples);
    f.read(reinterpret_cast<char*>(out.data()),
           static_cast<std::streamsize>(hdr.dataSize));

    AP_LOGI("readPcmWav: %zu samples from %s", numSamples, path.c_str());
    return numSamples;
}

bool writePcmWav(const std::string& path,
                 const std::vector<int16_t>& samples,
                 int sampleRate) {
    std::ofstream f(path, std::ios::binary);
    if (!f) { AP_LOGE("Cannot write WAV: %s", path.c_str()); return false; }

    const uint32_t dataSize  = static_cast<uint32_t>(samples.size() * 2);
    const uint32_t byteRate  = static_cast<uint32_t>(sampleRate * 2);

    RiffWav hdr;
    memcpy(hdr.riff,  "RIFF", 4);
    hdr.chunkSize    = 36 + dataSize;
    memcpy(hdr.wave,  "WAVE", 4);
    memcpy(hdr.fmt_,  "fmt ", 4);
    hdr.subchunk1Sz  = 16;
    hdr.audioFmt     = 1;
    hdr.channels     = 1;
    hdr.sampleRate   = static_cast<uint32_t>(sampleRate);
    hdr.byteRate     = byteRate;
    hdr.blockAlign   = 2;
    hdr.bitsPerSample= 16;
    memcpy(hdr.data,  "data", 4);
    hdr.dataSize     = dataSize;

    f.write(reinterpret_cast<const char*>(&hdr), sizeof(hdr));
    f.write(reinterpret_cast<const char*>(samples.data()),
            static_cast<std::streamsize>(dataSize));

    AP_LOGI("writePcmWav: %zu samples → %s", samples.size(), path.c_str());
    return f.good();
}

// ─────────────────────────────────────────────────────────────────────────────
// JNI helpers
// ─────────────────────────────────────────────────────────────────────────────
static std::string jstr(JNIEnv* env, jstring s) {
    if (!s) return {};
    const char* c = env->GetStringUTFChars(s, nullptr);
    std::string r(c);
    env->ReleaseStringUTFChars(s, c);
    return r;
}

// ─────────────────────────────────────────────────────────────────────────────
// JNI entry point: com.example.circadian_lingo.AudioProcessorJni.processWithVad
// ─────────────────────────────────────────────────────────────────────────────
extern "C"
JNIEXPORT jstring JNICALL
Java_com_example_circadian_1lingo_AudioProcessorJni_processWithVad(
        JNIEnv*  env,
        jobject  /* thiz */,
        jstring  inputWavPath,
        jstring  modelPath,
        jstring  outputDir) {

    const std::string wavPath   = jstr(env, inputWavPath);
    const std::string modelFile = jstr(env, modelPath);
    const std::string outDir    = jstr(env, outputDir);

    AP_LOGI("processWithVad | wav=%s | model=%s | outDir=%s",
            wavPath.c_str(), modelFile.c_str(), outDir.c_str());

    // ── 1. Read decoded PCM WAV ───────────────────────────────────────────
    std::vector<int16_t> rawSamples;
    if (readPcmWav(wavPath, rawSamples) == 0) {
        return env->NewStringUTF(R"({"error":"WAV_READ_FAILED"})");
    }

    // ── 2. Load Silero VAD session ────────────────────────────────────────
    SileroVad vad(modelFile);
    if (!vad.isValid()) {
        return env->NewStringUTF(R"({"error":"ONNX_LOAD_FAILED"})");
    }

    // ── 3. Slide 512-sample windows; keep speech chunks ──────────────────
    std::vector<float> state;  // zero-initialised by SileroVad::runWindow
    
    struct SpeechSegment {
        long long start_ms;
        long long end_ms;
    };
    std::vector<SpeechSegment> segments;

    int totalWindows  = 0;
    int speechWindows = 0;
    const int W = SileroVad::WINDOW_SIZE;

    // Normalisation scratch buffer (reused per window).
    std::vector<float> floatWindow(W);

    bool inSpeech = false;
    long long current_start_sample = -1;
    int postPaddingRemaining = 0;

    for (size_t offset = 0; offset + W <= rawSamples.size(); offset += W) {
        // Normalise int16 → float32 [-1, 1]
        for (int i = 0; i < W; ++i) {
            floatWindow[i] = rawSamples[offset + i] / 32768.0f;
        }

        const float prob = vad.runWindow(floatWindow.data(), state);
        ++totalWindows;

        if (prob >= SPEECH_THRESHOLD) {
            if (!inSpeech) {
                inSpeech = true;
                // Add pre-padding
                long long start = static_cast<long long>(offset) - VAD_PADDING_SAMPLES;
                current_start_sample = (start < 0) ? 0 : start;
            }
            postPaddingRemaining = VAD_PADDING_SAMPLES;
            ++speechWindows;
        } else {
            if (inSpeech) {
                postPaddingRemaining -= W;
                if (postPaddingRemaining <= 0) {
                    inSpeech = false;
                    long long end_sample = static_cast<long long>(offset) + W;
                    if (end_sample > rawSamples.size()) end_sample = rawSamples.size();
                    
                    segments.push_back({
                        current_start_sample * 1000LL / 16000LL,
                        end_sample * 1000LL / 16000LL
                    });
                }
            }
        }
    }

    if (inSpeech) {
        long long end_sample = rawSamples.size();
        segments.push_back({
            current_start_sample * 1000LL / 16000LL,
            end_sample * 1000LL / 16000LL
        });
    }

    AP_LOGI("VAD: %d/%d windows kept (%.0f%%), %zu segments found",
            speechWindows, totalWindows,
            totalWindows ? 100.0 * speechWindows / totalWindows : 0.0,
            segments.size());

    // Generate JSON string
    std::ostringstream json;
    json << "[";
    for (size_t i = 0; i < segments.size(); ++i) {
        json << "{\"start_ms\":" << segments[i].start_ms 
             << ",\"end_ms\":" << segments[i].end_ms << "}";
        if (i < segments.size() - 1) json << ",";
    }
    json << "]";

    AP_LOGI("VAD Output JSON: %s", json.str().c_str());
    return env->NewStringUTF(json.str().c_str());
}
