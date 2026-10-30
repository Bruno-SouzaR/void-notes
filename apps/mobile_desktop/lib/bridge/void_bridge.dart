import 'dart:async';

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
}

/// Local in-memory bridge mock used for widget tests and standalone UI development.
class MockVoidBridge implements VoidBridge {
  final List<DirectiveNote> _notes = [];
  bool _silent = false;

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
    return ['TriggerHaptic(LightTap)'];
  }

  @override
  Future<void> cancelActiveSession() async {}

  @override
  Future<List<DirectiveNote>> listTodayNotes() async {
    return List.unmodifiable(_notes);
  }

  @override
  Future<DirectiveNote?> revokeLatestDirective() async {
    if (_notes.isNotEmpty) {
      return _notes.removeLast();
    }
    return null;
  }

  @override
  Future<void> setSilentMode(bool enabled) async {
    _silent = enabled;
  }

  void addMockNote(DirectiveNote note) {
    _notes.insert(0, note);
  }
}
