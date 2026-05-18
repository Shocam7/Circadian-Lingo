#pragma once
// AudioProcessor.h — JNI entry point for the Silero VAD silence-stripping pipeline.
//
// Called from Kotlin: AudioProcessorJni.processWithVad()
//
// Pipeline inside this JNI call:
//   1. Read 16kHz mono 16-bit PCM WAV from inputWavPath
//   2. Slide a 512-sample window; run SileroVad::runWindow() per chunk
//   3. Collect speech-positive chunks (prob >= threshold)
//   4. Write trimmed WAV to outputDir/trimmed_<ts>.wav
//   5. Return trimmed WAV path (or JSON error string)

#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>

#define AP_TAG "AudioProcessor"
#define AP_LOGI(...) __android_log_print(ANDROID_LOG_INFO,  AP_TAG, __VA_ARGS__)
#define AP_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, AP_TAG, __VA_ARGS__)

static constexpr float SPEECH_THRESHOLD = 0.85f;
static constexpr int   VAD_PADDING_MS   = 400; // Capture 400ms before and after speech
static constexpr int   VAD_PADDING_SAMPLES = (VAD_PADDING_MS * 16000) / 1000; // 6400 samples

// Reads a 16kHz mono 16-bit PCM WAV; returns sample count or 0 on failure.
size_t readPcmWav(const std::string& path, std::vector<int16_t>& outSamples);

// Writes a 16kHz mono 16-bit PCM WAV with a standard 44-byte header.
bool writePcmWav(const std::string& path,
                 const std::vector<int16_t>& samples,
                 int sampleRate = 16000);

extern "C" {
    // JNI mangling: com.example.circadian_lingo.AudioProcessorJni.processWithVad()
    JNIEXPORT jstring JNICALL
    Java_com_example_circadian_1lingo_AudioProcessorJni_processWithVad(
        JNIEnv* env,
        jobject thiz,
        jstring inputWavPath,
        jstring modelPath,
        jstring outputDir
    );
}
