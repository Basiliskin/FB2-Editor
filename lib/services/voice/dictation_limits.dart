/// The longest single Dictation: Whisper's decode window. Capture stops by
/// itself here and what was said up to this point is still transcribed.
const dictationMaxDuration = Duration(seconds: 30);

/// The countdown shows for this long before the limit.
const dictationCountdown = Duration(seconds: 5);

/// A recording whose loudest 100 ms stays below this RMS level (0 to 1) is
/// treated as silence and not transcribed: Whisper invents words from quiet
/// noise. Measured on a phone: a quiet room 0.009 to 0.017, speech about 0.12.
const dictationMinLoudness = 0.025;
