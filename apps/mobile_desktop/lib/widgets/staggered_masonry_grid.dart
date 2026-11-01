import 'package:flutter/material.dart';
import '../bridge/void_bridge.dart';
import '../theme/void_theme.dart';
import 'directive_card.dart';

/// Responsive Masonry Grid that distributes cards across N columns without horizontal jumps.
class StaggeredMasonryGrid extends StatelessWidget {
  final List<DirectiveNote> notes;
  final VoidBridge bridge;
  final int numColumns;
  final bool isGridView;
  final bool isLoading;
  final Map<String, Set<int>> checkedMap;
  final Function(String noteId, Set<int> updatedChecked)? onCheckedUpdated;

  const StaggeredMasonryGrid({
    Key? key,
    required this.notes,
    required this.bridge,
    required this.numColumns,
    required this.isGridView,
    required this.isLoading,
    required this.checkedMap,
    this.onCheckedUpdated,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: VoidTheme.accent),
      );
    }

    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notes, size: 48, color: VoidTheme.textSecondary.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text(
              'Nenhuma nota encontrada.',
              style: TextStyle(
                color: VoidTheme.textSecondary.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // List view (1 column)
    if (!isGridView || numColumns <= 1) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: notes.length,
        itemBuilder: (context, idx) {
          final note = notes[idx];
          return DirectiveCard(
            key: ValueKey<String>(note.id),
            note: note,
            bridge: bridge,
            initialChecked: checkedMap[note.id] ?? const {},
            onCheckedUpdated: (updated) => onCheckedUpdated?.call(note.id, updated),
          );
        },
      );
    }

    // Multi-column Masonry Waterfall
    final columns = List.generate(numColumns, (_) => <Widget>[]);
    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      columns[i % numColumns].add(
        DirectiveCard(
          key: ValueKey<String>(note.id),
          note: note,
          bridge: bridge,
          initialChecked: checkedMap[note.id] ?? const {},
          onCheckedUpdated: (updated) => onCheckedUpdated?.call(note.id, updated),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(numColumns, (colIdx) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: colIdx == 0 ? 0 : 6,
                right: colIdx == numColumns - 1 ? 0 : 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: columns[colIdx],
              ),
            ),
          );
        }),
      ),
    );
  }
}
