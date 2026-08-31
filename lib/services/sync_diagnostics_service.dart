import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A small rolling log for diagnosing sync failures on a device.
///
/// Entries intentionally exclude record details, local file paths, pairing
/// secrets, and device tokens. Logging must never affect normal sync work.
class SyncDiagnosticsService {
  static const _fileName = 'tally_sync_diagnostics.log';
  static const _maxBytes = 256 * 1024;
  static const _retainedCharacters = 96 * 1024;

  Future<void> _writeQueue = Future.value();

  Future<File> _logFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, _fileName));
  }

  Future<void> log(String event) {
    final message = event.replaceAll(RegExp(r'\s+'), ' ').trim();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _logFile();
        if (await file.exists() && await file.length() >= _maxBytes) {
          final current = await file.readAsString();
          final retained = current.length > _retainedCharacters
              ? current.substring(current.length - _retainedCharacters)
              : current;
          await file.writeAsString(
            '[diagnostics log rolled over]\n$retained',
            flush: true,
          );
        }
        final timestamp = DateTime.now().toUtc().toIso8601String();
        await file.writeAsString(
          '$timestamp  $message\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Diagnostics are best-effort and must never stop a business record.
      }
    });
    return _writeQueue;
  }

  Future<String> read() async {
    try {
      final file = await _logFile();
      if (!await file.exists()) return 'No sync diagnostics have been recorded yet.';
      final contents = await file.readAsString();
      if (contents.isEmpty) return 'No sync diagnostics have been recorded yet.';
      return contents;
    } catch (_) {
      return 'The diagnostic log could not be read on this device.';
    }
  }

  Future<String> location() async {
    try {
      return (await _logFile()).path;
    } catch (_) {
      return _fileName;
    }
  }

  static String errorSummary(Object error) {
    final summary = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return summary.length <= 240 ? summary : '${summary.substring(0, 237)}…';
  }
}
