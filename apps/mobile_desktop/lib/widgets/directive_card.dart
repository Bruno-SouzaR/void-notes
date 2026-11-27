import 'package:flutter/material.dart';
import '../bridge/void_bridge.dart';
import '../screens/note_detail_screen.dart';
import '../theme/void_theme.dart';
import '../utils/directive_parser.dart';
import 'confirm_delete_dialog.dart';

/// Isolated leaf component for displaying an individual directive note.
/// Manages its own hover and checklist animations to prevent expensive parent rebuilds.
class DirectiveCard extends StatefulWidget {
  final DirectiveNote note;
  final VoidBridge bridge;
  final Set<int> initialChecked;
  final Function(Set<int> updatedChecked)? onCheckedUpdated;
  final VoidCallback? onDeleted;

  const DirectiveCard({
    super.key,
    required this.note,
    required this.bridge,
    this.initialChecked = const {},
    this.onCheckedUpdated,
    this.onDeleted,
  });

  @override
  State<DirectiveCard> createState() => _DirectiveCardState();
}

class _DirectiveCardState extends State<DirectiveCard> {
  bool _isHovered = false;
  late Set<int> _checkedIndices;
  late ParsedDirective _parsed;

  @override
  void initState() {
    super.initState();
    _checkedIndices = Set<int>.from(widget.initialChecked);
    _parsed = DirectiveParser.parse(widget.note.content);
  }

  @override
  void didUpdateWidget(covariant DirectiveCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.content != widget.note.content) {
      _parsed = DirectiveParser.parse(widget.note.content);
    }
    if (oldWidget.initialChecked != widget.initialChecked) {
      _checkedIndices = Set<int>.from(widget.initialChecked);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await confirmDeleteDialog(context, noteTitle: _parsed.title);
    if (!confirmed) return;

    final removed = await widget.bridge.deleteNote(widget.note);
    if (removed) {
      widget.onDeleted?.call();
    }
  }

  void _toggleItem(int index) {
    setState(() {
      if (_checkedIndices.contains(index)) {
        _checkedIndices.remove(index);
      } else {
        _checkedIndices.add(index);
      }
    });
    widget.onCheckedUpdated?.call(_checkedIndices);
  }

  @override
  Widget build(BuildContext context) {
    final totalItems = _parsed.items.length;
    final checkedCount = _checkedIndices.length;
    final targetProgress = totalItems > 0 ? (checkedCount / totalItems) : 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: VoidTheme.surface,
          borderRadius: BorderRadius.circular(VoidTheme.radiusCard),
          border: Border.all(
            color: _isHovered ? VoidTheme.accent : VoidTheme.border,
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: VoidTheme.accent.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(VoidTheme.radiusCard),
          child: InkWell(
            borderRadius: BorderRadius.circular(VoidTheme.radiusCard),
            onLongPress: () => _confirmDelete(context),
            onTap: () async {
              final deletedInDetail = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => NoteDetailScreen(
                    note: widget.note,
                    bridge: widget.bridge,
                    initialItems: _parsed.items.isNotEmpty ? _parsed.items : [widget.note.content],
                    initialChecked: _checkedIndices,
                    onCheckedUpdated: (updated) {
                      setState(() {
                        _checkedIndices = Set<int>.from(updated);
                      });
                      widget.onCheckedUpdated?.call(_checkedIndices);
                    },
                  ),
                ),
              );
              if (deletedInDetail == true) {
                widget.onDeleted?.call();
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + delete affordance (hover only)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _parsed.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: VoidTheme.textPrimary,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (_isHovered && widget.onDeleted != null)
                        GestureDetector(
                          onTap: () => _confirmDelete(context),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8, top: 2),
                            child: Icon(Icons.delete_outline, size: 18, color: VoidTheme.textPrimary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Animated Progress Bar
                  if (_parsed.isList && totalItems > 1) ...[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: targetProgress),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 3,
                            backgroundColor: VoidTheme.pillBg,
                            valueColor: const AlwaysStoppedAnimation<Color>(VoidTheme.accent),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$checkedCount de $totalItems (${(targetProgress * 100).toInt()}%)',
                      style: TextStyle(
                        fontSize: 11,
                        color: VoidTheme.textSecondary.withValues(alpha: 0.7),
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Checklist Items
                  if (_parsed.items.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(_parsed.items.take(6).length, (idx) {
                        final isChecked = _checkedIndices.contains(idx);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: _parsed.isList ? () => _toggleItem(idx) : null,
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_parsed.isList)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, right: 8),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 180),
                                      child: Icon(
                                        isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                                        key: ValueKey<bool>(isChecked),
                                        size: 15,
                                        color: isChecked ? VoidTheme.accent : VoidTheme.inactiveDot,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 180),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isChecked
                                          ? VoidTheme.textSecondary.withValues(alpha: 0.35)
                                          : VoidTheme.textSecondary.withValues(alpha: 0.85),
                                      decoration: isChecked ? TextDecoration.lineThrough : null,
                                      decorationColor: VoidTheme.textSecondary.withValues(alpha: 0.35),
                                      height: 1.3,
                                    ),
                                    child: Text(
                                      _parsed.items[idx],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),

                  if (_parsed.items.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${_parsed.items.length - 6} outros itens',
                        style: const TextStyle(fontSize: 11, color: VoidTheme.accent),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
