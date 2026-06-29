**Play Protect warning:** Because Circadian Lingo uses a background microphone service and an Accessibility Service together, Google Play Protect may block installation. To install the debug APK/release APK, tap **"More details"** on the warning dialog, then **"Install anyway"** or disable Play Protect globally. Re-enable it after installing, if you prefer.


# Circadian Lingo

**Learn a language from your day — privately, on your device.**

Circadian Lingo is a privacy-first language learning app for Android. Throughout your day, it passively captures ambient audio and screen context within a time window you define. Each evening, an on-device AI model turns those real-life moments into personalized vocabulary lessons, mini-stories, dialogues, and quizzes — all without sending a single byte to the cloud.

---

## How It Works

The app follows a simple daily cycle:

1. **Capture** — During your configured window (default 9 AM–5 PM), the app quietly records ambient audio and screen context as you go about your day.
2. **Review** — From the Privacy Dashboard, you can inspect, play back, or permanently delete any capture before a lesson is ever generated from it.
3. **Learn** — At your scheduled time (default 10 PM), the on-device Gemma model reads your day's context and generates a personalized lesson containing vocabulary cards, mini-stories, dialogues, flashcards, and quizzes.
4. **Retain** — The built-in FSRS spaced-repetition scheduler surfaces words again at optimal intervals so vocabulary sticks long-term.

---

## Features

### Ambient Context Engine
- **Audio capture** via a foreground microphone service; silence is automatically stripped using the Silero VAD model running on ONNX Runtime.
- **Screen context capture** via Android's Accessibility Service, which extracts on-screen text from apps you're actively using.
- A configurable daily capture window and per-day capture limits prevent information overload.
- A **Quick Settings tile** lets you start or stop capture directly from the notification shade.
- Captures older than one day are automatically purged on launch or resume.

### On-Device AI (Gemma via LiteRT-LM)
- A Gemma LLM (~2.59 GB) is downloaded once and runs entirely on-device — no API keys, no internet connection needed for inference.
- The model generates **Atomic Lesson Units (ALUs)**: vocabulary preview summaries, word cards with definitions and example sentences, mini-stories with translations, two-person dialogues, flashcard sets, and multiple-choice quizzes.
- A separate foreground service handles lesson generation so the process continues reliably in the background.

### FSRS Spaced Repetition
- Vocabulary retention is managed by a pure-Dart implementation of the **FSRS-4** algorithm (Ye 2022).
- Each word is tracked with a stability score, difficulty rating, and retrievability estimate; review intervals are scheduled so recall probability stays above 90%.
- Words that pass the mastery threshold are promoted to a permanent learned-words store.

### Privacy Dashboard
- Every capture — audio and screen — is listed with its timestamp and type.
- You can listen to raw audio captures, read extracted text, and delete individual items before any lesson is generated from them.
- Lesson generation can be triggered manually from a specific capture, or run automatically on the nightly schedule.

### Progress Screen
- A searchable list of every word you have mastered, with its meaning.
- A running count of total learned words.

### Localization & Language Setup
- Set your native language and target language during onboarding; both can be changed at any time in settings.
- Optionally localize the entire app UI into your native language (powered by the on-device model).

### Polished UI
- Glassmorphism design system built around "The Gentle Awakening" — a soft dawn palette of sky blue, lavender, and warm cream.
- Headlines in **Plus Jakarta Sans**, body text in **Lexend** (designed to reduce visual stress).
- Generous spacing, pill-shaped controls, organic blob decorations, and frosted-glass overlays.
- Biometric authentication (fingerprint / face) guards access to private captures.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI Framework | Flutter / Dart |
| Android Native | Kotlin |
| On-device LLM | Google Gemma via LiteRT-LM (`litertlm-android`) |
| Voice Activity Detection | Silero VAD model on ONNX Runtime (`onnxruntime-android 1.18.0`) |
| State Management | Riverpod (`flutter_riverpod 3.x`) |
| Spaced Repetition | FSRS-4 (pure Dart, persisted to `SharedPreferences`) |
| Background Scheduling | Android WorkManager (`work-runtime-ktx 2.9.0`) |
| Audio Playback | `just_audio` |
| Flashcard UI | `flutter_card_swiper` |
| Biometric Auth | `local_auth` |
| Fonts | Plus Jakarta Sans, Lexend via `google_fonts` |

### Android Services & Components

| Component | Purpose |
|---|---|
| `AudioCaptureService` | Foreground microphone recording (AAC → M4A) |
| `CircadianAccessibilityService` | Screen text extraction |
| `LessonGenerationForegroundService` | Background Gemma inference |
| `UITranslationForegroundService` | On-device UI localization |
| `CircadianTileService` | Quick Settings tile |
| `BootReceiver` | Reschedules lesson generation after device reboot |

---

## Requirements

- **Android 8.0 (API 26)** or higher
- **arm64-v8a** device (64-bit ARM)
- ~3 GB of free storage for the AI model
- Microphone permission for ambient audio capture
- Accessibility Service permission for screen context capture
- Notification permission (Android 13+)

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `^3.11.5`)
- Android Studio or VS Code with the Flutter extension
- An Android device or emulator running API 26+ (physical device strongly recommended for microphone and accessibility features)

### Build & Run

```bash
# Clone the repository
git clone https://github.com/Shocam7/Circadian-Lingo.git
cd Circadian-Lingo

# Install Flutter dependencies
flutter pub get

# Run in debug mode on a connected device
flutter run

# Build a release APK
flutter build apk --release
```

### First Launch

1. **The Brain** — Download the Gemma model (~2.59 GB). This is a one-time step. You can skip it and come back later, but lesson generation will not work until the model is present.
2. **Identity** — Select your native language and the language you want to learn. Optionally enable UI localization.
3. **Power Up** — Grant microphone and notification permissions. Enable the Accessibility Service in Android Settings to allow screen context capture.

---

## Architecture Overview

```
lib/
├── main.dart                  # App entry point, bottom navigation shell
├── models/
│   ├── alu.dart               # Atomic Lesson Unit types (WordCard, MiniStory, Quiz, …)
│   ├── alu_parser.dart        # Parses Gemma's structured text output into ALUs
│   └── word_review_record.dart
├── providers/
│   ├── audio_pipeline_provider.dart   # Recording state machine
│   ├── daily_captures_provider.dart   # Capture list, quality filtering, purge
│   ├── lesson_provider.dart           # Lesson generation & session state
│   ├── model_provider.dart            # Gemma download & status
│   ├── settings_provider.dart         # User settings (language, schedule, limits)
│   └── ui_strings_provider.dart       # Localized UI string management
├── screens/
│   ├── dashboard_screen.dart          # Home: listening button + insight cards
│   ├── privacy_dashboard_screen.dart  # Capture review & deletion
│   ├── daily_lesson_screen.dart       # Active lesson flow
│   ├── lesson_flow_screen.dart        # ALU card renderer
│   ├── progress_screen.dart           # Learned word list
│   └── onboarding_screen.dart         # Three-step setup wizard
├── services/
│   ├── audio_pipeline_service.dart    # Dart ↔ Kotlin MethodChannel bridge
│   ├── fsrs_service.dart              # FSRS-4 spaced repetition engine
│   ├── learned_words_service.dart     # Mastered vocabulary store
│   └── storage_cleanup_service.dart   # Stale file removal
├── theme/                             # AppTheme, colors, typography
└── widgets/                           # GlassCard, OrganicListeningButton, …

android/app/src/main/
├── kotlin/                    # AudioCaptureService, GemmaManager, VAD pipeline, …
├── cpp/                       # CMake config for ONNX Runtime native bridge
└── assets/                    # silero_vad.onnx model file
```

---

## Privacy Model

Circadian Lingo is designed from the ground up to keep your data on your device:

- All AI inference (transcription, lesson generation, UI translation) runs on the Gemma model stored locally on your phone.
- Ambient captures are stored in the app's private internal storage and are never uploaded anywhere.
- The Privacy Dashboard gives you a complete view of everything captured that day, with per-item deletion.
- All captures are automatically deleted at the start of each new day.
- The only outbound network request is the one-time model download during onboarding.

---

## Permissions

| Permission | Reason |
|---|---|
| `RECORD_AUDIO` | Ambient audio capture |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MICROPHONE` | Keep recording active while screen is off |
| `FOREGROUND_SERVICE_DATA_SYNC` | Run lesson generation in the background |
| `POST_NOTIFICATIONS` | Capture and lesson-ready notifications |
| `RECEIVE_BOOT_COMPLETED` | Reschedule nightly lesson generation after reboot |
| `USE_BIOMETRIC` / `USE_FINGERPRINT` | Optional biometric lock on captures |
| `WAKE_LOCK` | Keep CPU awake during lesson generation |
| `INTERNET` / `ACCESS_NETWORK_STATE` | One-time Gemma model download |
| Accessibility Service | On-screen text extraction for screen context captures |

---

## Contributing

Contributions are welcome. Please open an issue to discuss significant changes before submitting a pull request.

1. Fork the repository and create a feature branch.
2. Follow the existing code style; run `flutter analyze` before committing.
3. Write meaningful commit messages.
4. Open a pull request against `main`.

---

## License

This project does not currently include a license file. All rights are reserved by the author until a license is added.
