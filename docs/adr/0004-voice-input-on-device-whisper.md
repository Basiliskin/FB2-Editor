# Voice input is on-device Whisper, started by the user, on Android only

Dictation turns speech into text with the Whisper-small model running on the phone through sherpa-onnx, so audio never leaves the device. The 375 MB Speech Model is fetched only by a Model Download the user starts, and each file must match a built-in SHA-256 hash before it counts as installed. The feature sits behind a Settings switch that is off by default, and is Android only. We copied the recording and model code from the voice-note project rather than sharing a package, because the two apps will diverge and a shared package would couple their releases.

## Considered Options

- **Android `SpeechRecognizer`**: no model to download, but quality for Russian and Hebrew varies by device and audio may be sent to Google, which would contradict a privacy promise this app can keep.
- **Transcription through the user's LLM Provider**: reuses Provider setup, but sends audio off the device, and not every vendor offers speech-to-text.

## Consequences

Native libraries add about 20-30 MB to an install, and people who turn Dictation on spend 375 MB of storage. The app now requests `RECORD_AUDIO`, so the privacy policy and Play Data safety answers must say that audio stays on the device. Fixes to the copied code have to be made in both repositories.

## Language is detected, not taken from the book

Tried on a phone: with the language forced to the book's `<lang>`, Russian speech dictated into an
English book came out as an English translation (Whisper translates toward a forced language) and
looked like an ordinary result. So every recording uses Whisper's own detection (Auto) and the book's
language plays no part. The cost is that detection on a word or two can pick the wrong language.
