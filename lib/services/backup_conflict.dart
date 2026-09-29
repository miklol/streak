import 'dart:io';

import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';

class BackupConflict {
  const BackupConflict._();

  static const _setting = 'folderWorkConflict';

  static String _folderKey(String folder) {
    final key = Directory(folder).absolute.uri.normalizePath().toString();
    return Platform.isWindows ? key.toLowerCase() : key;
  }

  static String? pendingPayload(String folder) {
    final value = LocalStore.settingMap(_setting);
    if (value.isEmpty) return null;
    final read = RecordReader(value);
    return read.string('folder') == _folderKey(folder)
        ? read.string('payload')
        : null;
  }

  static Future<void> remember({
    required String folder,
    required String payload,
    required String record,
  }) => LocalStore.writeSetting(_setting, {
    'folder': _folderKey(folder),
    'payload': payload,
    'record': record,
  }, flush: true);

  static Future<void> clear(String folder) async {
    if (pendingPayload(folder) != null) {
      await LocalStore.writeSetting(_setting, <String, dynamic>{}, flush: true);
    }
  }
}
