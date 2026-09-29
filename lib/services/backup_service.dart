import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:streak/core/utils/app_dirs.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/services/import_service.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/habits/data/category.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/data/habit_note.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/services/vault_writer.dart';
import 'package:streak/services/backup_conflict.dart';

const _kBackupVersion = 3;
const _kAutoBackupKeep = 5;

class BackupFormatConflict extends FormatException {
  const BackupFormatConflict(super.message, this.payload);
  final String payload;
}

class BackupData {
  const BackupData({
    required this.habits,
    required this.notes,
    required this.focus,
    required this.todos,
    required this.categories,
    required this.skipped,
    this.exportedAt,
    this.work,
    this.source,
    this.supportsWorkTime = false,
  });

  final List<Habit> habits;
  final List<HabitNote> notes;
  final List<FocusSession> focus;
  final List<Todo> todos;
  final List<Category> categories;
  final int skipped;
  final DateTime? exportedAt;
  final WorkData? work;
  final String? source;
  final bool supportsWorkTime;

  bool get isEmpty =>
      habits.isEmpty &&
      notes.isEmpty &&
      focus.isEmpty &&
      todos.isEmpty &&
      (work == null || work!.isEmpty);
}

class BackupService {
  const BackupService._();

  static String _payloadFor(List<Habit> habits) {
    final payload = {
      'app': 'streak',
      'version': _kBackupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'habits': habits.map((h) => h.toMap()).toList(),
      'notes': LocalStore.readNotes().map((n) => n.toMap()).toList(),
      'focus':
          LocalStore.readFocusSessions(includeDeleted: true).map((f) => f.toMap()).toList(),
      'todos': LocalStore.readTodos().map((t) => t.toMap()).toList(),
      'categories':
          LocalStore.readCategories().map((c) => c.toMap()).toList(),
      'work': LocalStore.readWork().toMap(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static Future<Directory?> defaultBackupDir() async {
    final root = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await appDataDir();
    if (root == null) return null;
    return Directory('${root.path}/backups');
  }

  static Future<bool> ensureStorageAccess() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;
    final legacy = await Permission.storage.request();
    return legacy.isGranted;
  }

  static Future<String?> pickBackupFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return null;
    try {
      final probe = File('$path/.streak_write_test');
      await probe.writeAsString('ok');
      await probe.delete();
    } catch (_) {
      return '';
    }
    return path;
  }

  static Future<String?> runAuto({
    String folder = '',
    bool readable = true,
  }) async {
    final dir = folder.isEmpty
        ? await defaultBackupDir()
        : Directory(folder);
    if (dir == null) return null;
    if (BackupConflict.pendingPayload(dir.path) != null) {
      debugPrint('Automatic backup paused: unresolved Work or Goals conflict');
      return null;
    }
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
    } catch (_) {
      return null;
    }

    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final file = File('${dir.path}/streak_backup_$stamp.json');
    final habits = LocalStore.readHabits().values.toList();
    await file.writeAsString(_payloadFor(habits));

    try {
      if (readable) {
        await VaultWriter.write(
          Directory('${dir.path}/$vaultFolder'),
          habits: habits,
          categories: LocalStore.readCategories(),
          notes: LocalStore.readNotes(),
          todos: LocalStore.readTodos(),
          focus: LocalStore.readFocusSessions(),
          work: LocalStore.readWork(),
        );
      }
    } catch (e) {
      debugPrint('Could not write the readable copy: $e');
    }

    final old = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final stale in old.skip(_kAutoBackupKeep)) {
      try {
        stale.deleteSync();
      } catch (_) {}
    }
    return file.path;
  }

  static Future<bool> export(List<Habit> habits, {Rect? origin}) async {
    final content = _payloadFor(habits);
    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final name = 'streak_backup_$stamp.json';

    if (!isMobile) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save your Streak backup',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (path == null) return false;
      await File(path).writeAsString(content);
      return true;
    }

    final dir = await Directory.systemTemp.createTemp('streak_backup');
    final file = File('${dir.path}/$name');
    await file.writeAsString(content);

    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Streak backup',
      sharePositionOrigin: origin,
    );
    return result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.dismissed;
  }

  static Future<BackupData> read() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a Streak backup file',
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      throw Exception('No file selected');
    }

    final picked = result.files.single;
    List<int>? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      try {
        bytes = await File(picked.path!).readAsBytes();
      } catch (e) {
        debugPrint('Could not read ${picked.path}: $e');
        throw Exception('That file could not be read');
      }
    }
    if (bytes == null) {
      throw Exception('Could not read the selected file');
    }
    if (ImportService.looksLikeZip(bytes) ||
        ImportService.looksLikeSqlite(bytes)) {
      throw Exception(
        'That is an export from another app, not a Streak backup. '
        'Use "Import from another app" for it.',
      );
    }

    return parse(const Utf8Decoder(allowMalformed: true).convert(bytes));
  }

  static BackupData parse(String raw) {
    dynamic decoded;
    try {
      decoded = json.decode(raw);
    } catch (_) {
      throw Exception('That file is not a valid backup');
    }

    final List<dynamic> entries;
    final Map<String, dynamic> root;
    if (decoded is List) {
      entries = decoded;
      root = const {};
    } else if (decoded is Map &&
        (decoded['habits'] is List || decoded.containsKey('work'))) {
      if (decoded.containsKey('habits') && decoded['habits'] is! List) {
        throw const FormatException('Invalid habits collection in backup');
      }
      entries = decoded['habits'] as List? ?? const [];
      root = Map<String, dynamic>.from(decoded);
    } else {
      throw Exception('Unrecognised backup format');
    }

    final version = root['version'];
    if (version != null &&
        (version is! int || version < 1 || version > _kBackupVersion)) {
      throw BackupFormatConflict('Unsupported backup version', raw);
    }
    // Work data is a linked graph: rejecting it is safer than skipping records.
    WorkData? work;
    if (root.containsKey('work')) {
      try {
        work = WorkData.fromMap(RecordReader.object(root['work']));
      } on FormatException catch (e) {
        throw BackupFormatConflict(e.message, raw);
      } on ArgumentError catch (e) {
        throw BackupFormatConflict('Invalid Work or Goals data: ${e.message}', raw);
      }
    }
    var skipped = 0;
    List<T> collect<T>(Object? source, T Function(Map<String, dynamic>) build,
        {bool strict = false}) {
      if (source is! List) {
        if (strict) throw BackupFormatConflict('Invalid focus collection', raw);
        return <T>[];
      }
      final out = <T>[];
      for (final item in source) {
        if (item is! Map) {
          if (strict) throw BackupFormatConflict('Invalid focus record', raw);
          skipped++;
          continue;
        }
        try {
          out.add(build(Map<String, dynamic>.from(item)));
        } catch (error) {
          if (strict || item.containsKey('target')) {
            throw BackupFormatConflict('Invalid focus record: $error', raw);
          }
          skipped++;
        }
      }
      return out;
    }

    final habits = collect(entries, Habit.fromMap);
    final data = BackupData(
      habits: habits,
      notes: collect(root['notes'], HabitNote.fromMap),
      focus: collect(root['focus'], FocusSession.fromMap, strict: version == 3),
      todos: collect(root['todos'], Todo.fromMap),
      categories: collect(root['categories'], Category.fromMap),
      skipped: skipped,
      exportedAt: DateTime.tryParse((root['exportedAt'] ?? '') as String),
      work: work,
      source: raw,
      supportsWorkTime: version == 3,
    );

    if (data.isEmpty) throw Exception('No records found in that file');
    return data;
  }

  static Future<void> restore(BackupData data, {bool replace = false}) =>
      LocalStore.guardWrites(() async {
        if (data.isEmpty) {
          throw const FormatException('Cannot restore empty data');
        }
        if (LocalStore.settingMap('focusActive')['open'] == true) {
          throw StateError('Finish the active focus session before restoring a backup');
        }
        final before = await LocalStore.updateWork((current) => current);
        final incoming = data.work;
        final work = incoming == null
            ? null
            : (replace ? incoming : before.merge(incoming));
        final currentFocus = LocalStore.readFocusSessions(includeDeleted: true);
        final preservedFocus = replace
            ? (data.supportsWorkTime ? <FocusSession>[] : currentFocus
                .where((session) => session.target.kind == FocusTargetKind.workTask).toList())
            : currentFocus;
        final focus = mergeFocusSessions(preservedFocus, data.focus);
        if (replace) {
          // A legacy backup has no authority to clear the new collections.
          await LocalStore.wipeContent(includeWork: false);
        }
        for (final habit in data.habits) {
          await LocalStore.writeHabit(habit);
        }
        for (final category in data.categories) {
          await LocalStore.writeCategory(category);
        }
        for (final note in data.notes) {
          await LocalStore.writeNote(note);
        }
        for (final session in focus) {
          await LocalStore.writeFocusSession(session);
        }
        for (final todo in data.todos) {
          await LocalStore.writeTodo(todo);
        }
        if (work != null) {
          await LocalStore.writeWork(work, expectedRevision: before.revision);
        }
      });

  static List<FocusSession> mergeFocusSessions(
    List<FocusSession> current, List<FocusSession> incoming,
  ) {
    final merged = {for (final session in current) session.id: session};
    for (final session in incoming) {
      final old = merged[session.id];
      if (old != null &&
          (old.target.kind == FocusTargetKind.workTask ||
              session.target.kind == FocusTargetKind.workTask) &&
          json.encode(old.toMap()) != json.encode(session.toMap())) {
        throw WorkConflict('focus:${session.id}');
      }
      merged[session.id] = session;
    }
    for (final session in incoming.where((session) =>
        session.target.kind == FocusTargetKind.workTask && !session.isDeleted)) {
      for (final span in focusSessionIntervals(session)) {
        if (focusIntervalOverlapsSessions(startedAt: span.startedAt,
            endedAt: span.endedAt, sessions: merged.values, ignoreId: session.id)) {
          throw WorkConflict('overlapping focus:${session.id}');
        }
      }
    }
    return merged.values.toList();
  }
}
