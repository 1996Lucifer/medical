import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Plays the calling module's ringtone plus short connected/ended cues.
///
/// Ported from kram's frontend-v2 SoundService (same asset, same
/// silent-switch-safe AudioContext) and extended with connected/ended tones,
/// since CallService's state machine here has a real "active" and "ended"
/// transition to hang cues off that kram's engine doesn't expose the same
/// way. Without any of this, CallScreen/IncomingCallOverlay change state
/// silently - easy to miss if the screen isn't being watched.
class CallSoundService {
  static final CallSoundService _instance = CallSoundService._internal();
  factory CallSoundService() => _instance;
  CallSoundService._internal();

  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _cuePlayer = AudioPlayer();
  bool _ringtoneInitialized = false;
  bool _isRinging = false;
  bool _cueContextSet = false;

  /// Without this, iOS defaults to an audio session category that respects
  /// the hardware silent switch and Android's stream routing is left
  /// unspecified - both mean "plays fine on web, silent on a real phone"
  /// even though the code path ran correctly. `respectSilence: false` would
  /// normally put iOS in the `.playback` category, but that category has no
  /// recording capability - found live: playConnected() fires this cue at
  /// the exact instant a call's ICE state reaches "connected"
  /// (call_service.dart), and playing it re-asserts `.playback` on iOS's
  /// *shared* AVAudioSession, ripping out the `.playAndRecord` category
  /// flutter_webrtc had just set up for the mic. Video kept working (no
  /// AVAudioSession involvement) while audio died in both directions right
  /// as the call connected. Explicitly requesting `.playAndRecord` here
  /// keeps the cues audible over the silent switch without ever taking the
  /// shared session out of recording mode.
  static final AudioContext _audibleContext = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.mixWithOthers,
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
      },
    ),
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: true,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.voiceCommunication,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  Future<void> init() async {
    // AudioCache.fetchToMemory takes two DIFFERENT, incompatible paths
    // depending on platform, both keyed off the same `prefix` + fileName:
    //  - web (_sanitizeURLForWeb) builds the request URL as literal
    //    'assets/$prefix$fileName' - it always adds its own 'assets/', so
    //    with the library's default prefix ('assets/') a plain
    //    'sounds/ringtone.wav' becomes 'assets/assets/sounds/ringtone.wav',
    //    a 404 (confirmed via curl) that <audio> reports as a decode/format
    //    error even though the real file is fine - it looks like a codec
    //    problem but it's a wrong-URL problem. Fix: prefix must be empty on
    //    web so the single 'assets/' the sanitizer adds is the only one.
    //  - native (rootBundle.load('$prefix$fileName')) does NOT add
    //    anything - it needs the FULL registered asset key, which already
    //    includes 'assets/' (pubspec's `assets: - assets/`). Zeroing the
    //    prefix here breaks native lookups outright ("Unable to load
    //    asset: sounds/ringtone.wav" - confirmed live on a real iPhone
    //    after applying the web-only fix without this platform split).
    // AssetSource call sites below always pass the bare 'sounds/x.wav'
    // form; this is what makes both platform paths resolve correctly.
    AudioCache.instance.prefix = kIsWeb ? '' : 'assets/';
    try {
      await AudioPlayer.global.setAudioContext(_audibleContext);
    } catch (e) {
      debugPrint('CallSoundService: failed to set global audio context: $e');
    }
  }

  Future<void> _ensureRingtoneReady() async {
    if (_ringtoneInitialized) return;
    await _ringtonePlayer.setAudioContext(_audibleContext);
    await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    await _ringtonePlayer.setSource(AssetSource('sounds/ringtone.wav'));
    _ringtoneInitialized = true;
  }

  /// Starts looping the ringtone. Safe to call repeatedly - a call already
  /// ringing just keeps ringing rather than restarting from the top.
  Future<void> startRinging() async {
    if (_isRinging) return;
    _isRinging = true;
    try {
      await _ensureRingtoneReady();
      await _ringtonePlayer.resume();
    } catch (e) {
      debugPrint('CallSoundService: failed to start ringtone: $e');
      _isRinging = false;
    }
  }

  /// Stops the ringtone. Called on accept, decline, the caller hanging up
  /// first, or the call otherwise leaving the "incoming" state.
  Future<void> stopRinging() async {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      await _ringtonePlayer.stop();
    } catch (e) {
      debugPrint('CallSoundService: failed to stop ringtone: $e');
    }
  }

  Future<void> _playCue(String assetPath) async {
    try {
      if (!_cueContextSet) {
        await _cuePlayer.setAudioContext(_audibleContext);
        _cueContextSet = true;
      }
      await _cuePlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('CallSoundService: failed to play $assetPath: $e');
    }
  }

  /// Plays once when a call reaches CallState.active (either side).
  /// Bare path, same convention as the ringtone above - AudioCache.prefix
  /// (set in init()) supplies the platform-correct 'assets/' handling.
  Future<void> playConnected() => _playCue('sounds/call_connected.wav');

  /// Plays once when a call reaches CallState.ended.
  Future<void> playEnded() => _playCue('sounds/call_ended.wav');

  Future<void> dispose() async {
    await _ringtonePlayer.dispose();
    await _cuePlayer.dispose();
  }
}
