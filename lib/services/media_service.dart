import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Saves photos and voice notes into the app's own folder so they survive
/// while the record is queued for the main POS system.
class MediaService {
  MediaService._();

  static Future<Directory> _attachmentsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'attachments'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Captures a photo with the camera and returns the saved file path.
  static Future<String?> capturePhoto() async {
    try {
      final file =
          await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      if (file == null) return null;
      return _persist(file);
    } catch (_) {
      return null;
    }
  }

  /// Picks an image (or screenshot) from the gallery and saves it.
  static Future<String?> pickGallery() async {
    try {
      final file =
          await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) return null;
      return _persist(file);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _persist(XFile file) async {
    final dir = await _attachmentsDir();
    var ext = p.extension(file.path);
    if (ext.isEmpty) ext = '.jpg';
    final target = p.join(
      dir.path,
      'img_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await File(file.path).copy(target);
    return target;
  }
}

/// Handles a single voice-note recording session.
class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _currentPath;

  bool get isRecording => _recording;
  Duration get elapsed => _elapsed;

  void _tick() {
    _elapsed += const Duration(seconds: 1);
  }

  /// Requests permission and starts recording. Returns false if denied.
  Future<bool> start() async {
    if (_recording) return true;
    final ok = await _recorder.hasPermission();
    if (!ok) return false;
    final dir = await MediaService._attachmentsDir();
    _currentPath = p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: _currentPath!,
    );
    _elapsed = Duration.zero;
    _recording = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return true;
  }

  /// Stops and returns the saved file path (null if nothing was recorded).
  Future<String?> stop() async {
    if (!_recording) return null;
    final path = await _recorder.stop();
    _timer?.cancel();
    _timer = null;
    _recording = false;
    return (path ?? _currentPath);
  }

  /// Cancels the session and deletes the partial file.
  Future<void> cancel() async {
    if (!_recording) return;
    await _recorder.cancel();
    _timer?.cancel();
    _timer = null;
    _recording = false;
    if (_currentPath != null) {
      final f = File(_currentPath!);
      if (await f.exists()) await f.delete();
    }
    _currentPath = null;
  }

  Future<void> dispose() async {
    if (_recording) await _recorder.stop();
    await _recorder.dispose();
  }
}

/// Simple playback of a saved voice note.
class VoicePlayer {
  VoicePlayer._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _configured = false;

  static Future<void> play(String path) async {
    await _player.stop();
    if (!_configured) {
      await _player.setReleaseMode(ReleaseMode.stop);
      _configured = true;
    }
    await _player.play(DeviceFileSource(path));
  }

  static Future<void> stop() => _player.stop();
}
