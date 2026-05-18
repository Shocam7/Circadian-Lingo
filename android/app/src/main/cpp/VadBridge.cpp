// VadBridge.cpp — Silero VAD ONNX Runtime implementation
#include "VadBridge.h"
#include <array>
#include <stdexcept>

// ── Meyer's singleton ORT environment ────────────────────────────────────────
// Created once per process; survives across multiple SileroVad instances.
Ort::Env& SileroVad::env() {
    static Ort::Env instance(ORT_LOGGING_LEVEL_WARNING, "SileroVAD");
    return instance;
}

// ── Constructor: load ONNX session ───────────────────────────────────────────
SileroVad::SileroVad(const std::string& modelPath) {
    try {
        Ort::SessionOptions opts;
        opts.SetIntraOpNumThreads(2);   // Silero VAD is tiny; 2 threads is sufficient
        opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        // ONNX Runtime on Android uses the std::string path overload.
        session_ = std::make_unique<Ort::Session>(env(), modelPath.c_str(), opts);

        VAD_LOGI("ONNX session created for: %s", modelPath.c_str());
    } catch (const Ort::Exception& e) {
        VAD_LOGE("Ort::Exception loading model '%s': %s", modelPath.c_str(), e.what());
        session_ = nullptr;
    } catch (const std::exception& e) {
        VAD_LOGE("std::exception loading model '%s': %s", modelPath.c_str(), e.what());
        session_ = nullptr;
    }
}

// ── runWindow: single 32ms inference step ────────────────────────────────────
float SileroVad::runWindow(const float*        windowSamples,
                           std::vector<float>& state) {
    if (!session_) {
        VAD_LOGE("runWindow() called on invalid session.");
        return -1.0f;
    }

    // Ensure state vector is the right size (zero-init on first call).
    if (state.size() != static_cast<size_t>(STATE_ELEMS)) state.assign(STATE_ELEMS, 0.f);

    try {
        auto memInfo = Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeCPU);

        // ── Build input tensors ───────────────────────────────────────────
        // 1. audio input:  [1, 576] (64 context + 512 new samples)
        std::vector<float> input_buffer(576, 0.0f);
        std::copy(_context.begin(), _context.end(), input_buffer.begin());
        std::copy(windowSamples, windowSamples + WINDOW_SIZE, input_buffer.begin() + 64);
        
        // Update context for next iteration with the last 64 floats of the current chunk
        std::copy(windowSamples + WINDOW_SIZE - 64, windowSamples + WINDOW_SIZE, _context.begin());

        std::array<int64_t, 2> inputShape = {1, 576};
        auto inputTensor = Ort::Value::CreateTensor<float>(
            memInfo,
            input_buffer.data(), 576,
            inputShape.data(), inputShape.size());

        // 2. sample rate: [1] int64 (always 16000)
        int64_t srVal = 16000;
        std::array<int64_t, 1> srShape = {1};
        auto srTensor = Ort::Value::CreateTensor<int64_t>(
            memInfo, &srVal, 1, srShape.data(), srShape.size());

        // 3. state: [2, 1, 128]
        std::array<int64_t, 3> stateShape = {2, 1, 128};
        auto stateTensor = Ort::Value::CreateTensor<float>(
            memInfo, state.data(), STATE_ELEMS, stateShape.data(), stateShape.size());

        // ── Assemble and run ──────────────────────────────────────────────
        const char* inputNames[]  = {"input", "sr", "state"};
        const char* outputNames[] = {"output", "stateN"};

        std::vector<Ort::Value> inputs;
        inputs.push_back(std::move(inputTensor));
        inputs.push_back(std::move(srTensor));
        inputs.push_back(std::move(stateTensor));

        auto outputs = session_->Run(
            Ort::RunOptions{nullptr},
            inputNames,  inputs.data(),  3,
            outputNames, 2);

        // ── Extract outputs ───────────────────────────────────────────────
        // speech probability
        float speechProb = outputs[0].GetTensorData<float>()[0];

        // Update LSTM state in-place for the next window.
        const float* stateNData = outputs[1].GetTensorData<float>();
        state.assign(stateNData, stateNData + STATE_ELEMS);

        return speechProb;

    } catch (const Ort::Exception& e) {
        VAD_LOGE("Ort::Exception during inference: %s", e.what());
        return -1.0f;
    }
}
