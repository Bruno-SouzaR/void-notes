import 'package:flutter_test/flutter_test.dart';
import 'package:void_notes/bridge/void_bridge.dart';
import 'package:void_notes/main.dart';
import 'package:void_notes/utils/directive_parser.dart';
import 'package:void_notes/widgets/directive_card.dart';
import 'package:void_notes/widgets/floating_search_pill.dart';

class FakeVoidBridge implements VoidBridge {
  final List<DirectiveNote> notes;
  bool _silent = false;
  String _model = 'small';

  FakeVoidBridge({required this.notes});

  @override
  bool get isSilent => _silent;

  @override
  String get selectedModel => _model;

  @override
  void setSelectedModel(String model) {
    _model = model;
  }

  @override
  Future<void> initEngine({
    required String dbPath,
    required String notesDir,
    required bool silentMode,
  }) async {
    _silent = silentMode;
  }

  @override
  Future<bool> deleteNote(DirectiveNote note) async {
    final before = notes.length;
    notes.removeWhere((candidate) => candidate.id == note.id);
    return notes.length < before;
  }

  @override
  Future<List<String>> listAvailableDates() async {
    return ['2026-11-01'];
  }

  @override
  Future<List<DirectiveNote>> listNotesForDate(String dateYmd) async {
    return notes;
  }

  @override
  Future<List<DirectiveNote>> listTodayNotes() async {
    return notes;
  }

  @override
  Future<DirectiveNote?> revokeLatestDirective() async {
    return notes.isNotEmpty ? notes.first : null;
  }

  @override
  Future<void> setSilentMode(bool enabled) async {
    _silent = enabled;
  }

  @override
  Future<List<String>> triggerPriorityOverride() async {
    return const [];
  }

  @override
  Future<void> cancelActiveSession() async {}
}

void main() {
  group('DirectiveParser Unit Tests', () {
    test('extracts title and items from comma/and separated shopping list', () {
      const input = 'Lista de compras: arroz, feijão e café.';
      expect(DirectiveParser.isChecklist(input), isTrue);

      final parsed = DirectiveParser.parse(input);
      expect(parsed.isList, isTrue);
      expect(parsed.title, equals('Lista de Compras'));
      expect(parsed.items, equals(['arroz', 'feijão', 'café']));
    });

    test('extracts title and body from free-form note', () {
      const input = 'Lembrar de pagar o condomínio amanhã cedo.';
      expect(DirectiveParser.isChecklist(input), isFalse);

      final parsed = DirectiveParser.parse(input);
      expect(parsed.isList, isFalse);
      expect(parsed.title, equals('Lembrar de pagar o condomínio'));
      expect(parsed.items, equals(['amanhã cedo.']));
    });
  });

  group('VoidApp UI Smoke Tests', () {
    testWidgets('renders search pill and directive cards cleanly', (WidgetTester tester) async {
      final now = DateTime.now();
      final fakeBridge = FakeVoidBridge(
        notes: [
          DirectiveNote(
            id: 'test-1',
            content: 'Lista de compras: leite, manteiga e pão.',
            audioDurationMs: 4200,
            rawTranscription: 'lista de compras leite manteiga e pao',
            createdAt: now,
            updatedAt: now,
            syncStatus: 'synced',
          ),
          DirectiveNote(
            id: 'test-2',
            content: 'Ligar para o banco amanha.',
            audioDurationMs: 2500,
            rawTranscription: 'ligar para o banco amanha',
            createdAt: now,
            updatedAt: now,
            syncStatus: 'synced',
          ),
        ],
      );

      await tester.pumpWidget(VoidApp(bridge: fakeBridge));
      await tester.pumpAndSettle();

      // Search pill should be rendered
      expect(find.byType(FloatingSearchPill), findsOneWidget);

      // Directive cards should be rendered
      expect(find.byType(DirectiveCard), findsNWidgets(2));
      expect(find.text('Lista de Compras'), findsOneWidget);
      expect(find.text('leite'), findsOneWidget);
      expect(find.text('manteiga'), findsOneWidget);

      // Tap on the card to open NoteDetailScreen
      await tester.tap(find.text('Lista de Compras'));
      await tester.pumpAndSettle();

      // Should be on detail screen with progress
      expect(find.text('PROGRESSO'), findsOneWidget);
    });
  });
}
