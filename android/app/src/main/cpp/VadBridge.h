#pragma once
// VadBridge.h — Silero VAD ONNX Runtime session wrapper (C++)
//
// Wraps a single Ort::Session for the silero_vad.onnx model.
// The caller is responsible for constructing this object once per
// processWithVad() call and destroying it afterwards (releases ~50 MB).
//
// Silero VAD v5 ONNX I/O contract:
//   Inputs:  "input" [1, 512] float32   — 32ms audio window
//            "sr"    [1]      int64     — sample rate (always 16000)
//            "state" [2,1,128] float32  — LSTM state
//   Outputs: "output"[1,1]    float32   — speech probability
//            "stateN"[2,1,128] float32  — updated LSTM state

#include <memory>
#include <string>
#include <vector>
#include <android/log.h>
#include "onnxruntime_cxx_api.h"

#define VAD_TAG "VadBridge"
#define VAD_LOGI(...) __android_log_print(ANDROID_LOG_INFO,  VAD_TAG, __VA_ARGS__)
#define VAD_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, VAD_TAG, __VA_ARGS__)

class SileroVad {
public:
    static constexpr int WINDOW_SIZE = 512;   // samples per inference step (32ms @ 16kHz)
    static constexpr int STATE_ELEMS = 256;   // 2 * 1 * 128 (flattened LSTM state)

    // Loads the ONNX session from modelPath.
    // Check isValid() after construction before calling runWindow().
    explicit SileroVad(const std::string& modelPath);
    ~SileroVad() = default;

    // Non-copyable; owns ORT session resources.
    SileroVad(const SileroVad&)            = delete;
    SileroVad& operator=(const SileroVad&) = delete;

    bool isValid() const { return session_ != nullptr; }

    // Runs one 32ms inference window.
    // @param windowSamples  Exactly WINDOW_SIZE float32 samples in [-1.0, 1.0]
    // @param state          LSTM state (STATE_ELEMS floats); updated in place
    // @return               Speech probability in [0.0, 1.0], or -1.0 on error
    float runWindow(const float*         windowSamples,
                    std::vector<float>&  state);

private:
    // Meyer's singleton: one ORT Env for the process lifetime (cheap to keep alive).
    static Ort::Env& env();

    std::unique_ptr<Ort::Session>    session_;
    Ort::AllocatorWithDefaultOptions allocator_;
    std::vector<float> _context{std::vector<float>(64, 0.0f)};
};
