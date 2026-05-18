# R8 rules to ignore missing JDK classes used by annotation processors at compile-time
-dontwarn javax.annotation.processing.**
-dontwarn javax.lang.model.**
-dontwarn com.google.auto.value.**

# --- Circadian Lingo AI Pipeline Protection ---

# 1. Protect LiteRT GenAI (The core Gemma engine)
-keep class com.google.ai.edge.litert.** { *; }
-keepclassmembers class com.google.ai.edge.litert.** { *; }

# 2. Protect MediaPipe (Required if using tasks-genai/multimodal)
-keep class com.google.mediapipe.** { *; }
-keepclassmembers class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate

# 3. Protect Protobufs (LiteRT uses these for model configuration)
-keep class com.google.protobuf.** { *; }
-keepclassmembers class com.google.protobuf.** { *; }

# 4. Critical: Prevent JNI/Reflection attribute stripping
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keepnames class * implements java.io.Serializable



# Protect JNI C++ Bindings from being obfuscated/deleted
-keep class com.example.circadian_lingo.AudioProcessorJni { *; }

# Protect ONNX Runtime Java layer
-keep class com.microsoft.onnxruntime.** { *; }

# Protect LiteRT GenAI / MediaPipe SDK
-keep class com.google.ai.edge.litertlm.** { *; }
-keep class com.google.mediapipe.** { *; }