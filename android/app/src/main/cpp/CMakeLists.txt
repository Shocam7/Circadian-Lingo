cmake_minimum_required(VERSION 3.22.1)
project(audio_pipeline VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── ONNX Runtime headers ──────────────────────────────────────────────────────
# The ONNX Runtime .so is provided by the Gradle `onnxruntime-android` AAR
# dependency and extracted to the system's library path automatically.
# We only need the headers here; download them from the GitHub release.
include(FetchContent)
FetchContent_Declare(
    onnxruntime_headers
    URL           https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.18.0/onnxruntime-android-1.18.0.aar
    URL_HASH      SHA256=C65855589C61B24D8A8CC821AC2F511F63EA2767150A56D94FB7BA2AAD145458
    DOWNLOAD_NAME onnxruntime-android-1.18.0.zip   # .zip so CMake auto-extracts
    DOWNLOAD_NO_PROGRESS TRUE
)
FetchContent_MakeAvailable(onnxruntime_headers)
# After extraction, headers are at:
#   ${onnxruntime_headers_SOURCE_DIR}/headers/onnxruntime_cxx_api.h  (and others)
# The .so files are at:
#   ${onnxruntime_headers_SOURCE_DIR}/jni/${ANDROID_ABI}/libonnxruntime.so

# Create imported library target pointing to the extracted .so
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION
        "${onnxruntime_headers_SOURCE_DIR}/jni/${ANDROID_ABI}/libonnxruntime.so"
)

# ── Our JNI shared library ────────────────────────────────────────────────────
add_library(audio_pipeline SHARED
    VadBridge.cpp
    AudioProcessor.cpp
)

target_include_directories(audio_pipeline PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${onnxruntime_headers_SOURCE_DIR}/headers
)

target_link_libraries(audio_pipeline
    PRIVATE
        onnxruntime
        android
        log
)

target_compile_options(audio_pipeline PRIVATE
    -O2
    -fvisibility=hidden
    -DNDEBUG
)
