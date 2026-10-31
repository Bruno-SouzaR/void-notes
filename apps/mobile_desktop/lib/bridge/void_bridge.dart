import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Dart representation of a DirectiveNote from the Rust core.
class DirectiveNote {
  final String id;
  final String content;
  final String rawTranscription;
  final int audioDurationMs;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String syncStatus;

  DirectiveNote({
    required this.id,
    required this.content,
    required this.rawTranscription,
    required this.audioDurationMs,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
  });

  factory DirectiveNote.fromJson(Map<String, dynamic> json) {
    return DirectiveNote(
      id: json['id'] as String,
      content: json['content'] as String,
      rawTranscription: json['raw_transcription'] as String,
      audioDurationMs: json['audio_duration_ms'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at'] as String) : null,
      syncStatus: json['sync_status'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'raw_transcription': rawTranscription,
    'audio_duration_ms': audioDurationMs,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
    'sync_status': syncStatus,
  };
}

/// Abstract bridge interface connecting Flutter to the native Rust core.
abstract class VoidBridge {
  Future<void> initEngine({
    required String dbPath,
    required String notesDir,
    required bool silentMode,
  });

  Future<List<String>> triggerPriorityOverride();

  Future<void> cancelActiveSession();

  Future<List<DirectiveNote>> listTodayNotes();

  Future<DirectiveNote?> revokeLatestDirective();

  Future<void> setSilentMode(bool enabled);

  void setSelectedModel(String model);

  String get selectedModel;
}

/// Bridge reading directly from the Local-First Markdown daily mirror and triggering recordings.
class LocalFileVoidBridge implements VoidBridge {
  final Directory notesDirectory;
  final Directory projectRoot;
  bool _silent = false;
  String _selectedModel = 'base';

  LocalFileVoidBridge({required this.notesDirectory, required this.projectRoot});

  @override
  void setSelectedModel(String model) {
    _selectedModel = model;
  }

  @override
  String get selectedModel => _selectedModel;

  @override
  Future<void> initEngine({
    required String dbPath,
    required String notesDir,
    required bool silentMode,
  }) async {
    _silent = silentMode;
  }

  @override
  Future<List<String>> triggerPriorityOverride() async {
    try {
      final scriptPath = '${projectRoot.path}/record_test.sh';
      final scriptFile = File(scriptPath);
      if (await scriptFile.exists()) {
        final result = await Process.run(
          scriptPath,
          ['5', _selectedModel],
          workingDirectory: projectRoot.path,
          environment: {
            'PATH': '/usr/bin:/usr/local/bin:${Platform.environment['PATH'] ?? ''}',
          },
        );
        debugPrint('[void-notes] record_test.sh exitCode: ${result.exitCode}');
        if (result.stdout.toString().isNotEmpty) {
          debugPrint('[void-notes] record_test.sh stdout: ${result.stdout}');
        }
        if (result.stderr.toString().isNotEmpty) {
          debugPrint('[void-notes] record_test.sh stderr: ${result.stderr}');
        }
      } else {
        debugPrint('[void-notes] Script not found at: $scriptPath');
      }
    } catch (e) {
      debugPrint('[void-notes] Error executing triggerPriorityOverride: $e');
    }
    return ['TriggerHaptic(LightTap)'];
  }

  @override
  Future<void> cancelActiveSession() async {}

  @override
  Future<List<DirectiveNote>> listTodayNotes() async {
    final now = DateTime.now();
    final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File('${notesDirectory.path}/$todayStr.md');

    if (!await file.exists()) {
      return [];
    }

    final lines = await file.readAsLines();
    final List<DirectiveNote> notes = [];

    // Parse lines formatted as: - **[HH:MM:SS]** content
    final regex = RegExp(r'^- \*\*\[(\d{2}:\d{2}:\d{2})\]\*\* (.+)$');

    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      final match = regex.firstMatch(line);
      if (match != null) {
        final timeStr = match.group(1)!;
        final content = match.group(2)!;
        final timeParts = timeStr.split(':');
        final createdAt = DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
          int.parse(timeParts[2]),
        );

        notes.add(DirectiveNote(
          id: 'note_$i',
          content: content,
          rawTranscription: content,
          audioDurationMs: 4000,
          createdAt: createdAt,
          updatedAt: createdAt,
          syncStatus: 'pending',
        ));
      }
    }

    return notes;
  }

  @override
  Future<DirectiveNote?> revokeLatestDirective() async {
    final notes = await listTodayNotes();
    if (notes.isEmpty) return null;
    final latest = notes.first;

    final now = DateTime.now();
    final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File('${notesDirectory.path}/$todayStr.md');

    if (await file.exists()) {
      final lines = await file.readAsLines();
      for (var i = lines.length - 1; i >= 0; i--) {
        if (lines[i].trim().startsWith('- **[')) {
          lines.removeAt(i);
          break;
        }
      }
      await file.writeAsString(lines.join('\n'));
    }

    return latest;
  }

  @override
  Future<void> setSilentMode(bool enabled) async {
    _silent = enabled;
  }
}
