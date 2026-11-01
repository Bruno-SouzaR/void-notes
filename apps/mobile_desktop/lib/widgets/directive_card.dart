import 'package:flutter/material.dart';
import '../bridge/void_bridge.dart';
import '../screens/note_detail_screen.dart';
import '../theme/void_theme.dart';

/// Isolated leaf component for displaying an individual directive note.
/// Manages its own hover and checklist animations to prevent expensive parent rebuilds.
class DirectiveCard extends StatefulWidget {
  final DirectiveNote note;
  final VoidBridge bridge;
  final Set<int> initialChecked;
  final Function(Set<int> updatedChecked)? onCheckedUpdated;

  const DirectiveCard({
    Key? key,
    required this.note,
    required this.bridge,
    this.initialChecked = const {},
    this.onCheckedUpdated,
  }) : super(key: key);

  @override
  State<DirectiveCard> createState() => _DirectiveCardState();
}

class _DirectiveCardState extends State<DirectiveCard> {
  bool _isHovered = false;
  late Set<int> _checkedIndices;
  late final String _title;
  late final List<String> _items;
  late final bool _isList;

  @override
  void initState() {
    super.initState();
    _checkedIndices = Set<int>.from(widget.initialChecked);
    final parsed = _parseContent(widget.note.content);
    _title = parsed.$1;
    _items = parsed.$2;
    _isList = parsed.$3;
  }

  (String, List<String>, bool) _parseContent(String rawContent) {
    var text = rawContent.trim();
    final lower = text.toLowerCase();
    final isList = lower.contains('lista') ||
        lower.contains('mercado') ||
        lower.contains('compras') ||
        lower.contains('comprar') ||
        text.contains('- [ ]') ||
        text.contains('- [x]');

    if (isList) {
      final prefixRegex = RegExp(
        r'^(cria uma |fazer uma |nova |nota para o |nota para um )?lista( de compras| de mercado)?[:., -]*',
        caseSensitive: false,
      );
      final match = prefixRegex.firstMatch(text);
      String title = 'Lista de Compras';
      if (match != null) {
        final matchedText = match.group(0)!.trim().replaceAll(RegExp(r'[:., -]+$'), '');
        if (matchedText.isNotEmpty) {
          title = matchedText[0].toUpperCase() + matchedText.substring(1);
        }
        text = text.substring(match.end).trim();
      }

      List<String> rawItems = [];
      if (text.contains('\n')) {
        rawItems = text.split('\n');
      } else if (text.contains(',') || text.contains(';')) {
        rawItems = text.split(RegExp(r'[,;]'));
      } else {
        rawItems = [text];
      }

      List<String> items = [];
      for (var item in rawItems) {
        var cleaned = item.trim().replaceAll(RegExp(r'^\s*[-*•]\s*(\[[ x]\]\s*)?'), '').trim();
        if (cleaned.contains(' e ') && !cleaned.toLowerCase().startsWith('e ')) {
          for (var s in cleaned.split(' e ')) {
            final st = s.trim().replaceAll(RegExp(r'\.+$'), '');
            if (st.isNotEmpty) items.add(st);
          }
        } else {
          final st = cleaned.replaceAll(RegExp(r'\.+$'), '');
          if (st.isNotEmpty) items.add(st);
        }
      }

      if (items.isEmpty && text.isNotEmpty) {
        items = [text];
      }
      return (title, items, true);
    } else {
      String title;
      String body;
      if (text.contains('.')) {
        final parts = text.split('.');
        title = parts[0].trim();
        body = parts.sublist(1).join('.').trim();
      } else {
        final words = text.split(' ');
        if (words.length > 5) {
          title = words.take(5).join(' ');
          body = words.skip(5).join(' ');
        } else {
          title = text;
          body = '';
        }
      }
      return (title, body.isNotEmpty ? [body] : [], false);
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
    final totalItems = _items.length;
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
                    color: VoidTheme.accent.withOpacity(0.25),
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
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NoteDetailScreen(
                    note: widget.note,
                    bridge: widget.bridge,
                    initialItems: _items.isNotEmpty ? _items : [widget.note.content],
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
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: VoidTheme.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Animated Progress Bar
                  if (_isList && totalItems > 1) ...[
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
                        color: VoidTheme.textSecondary.withOpacity(0.7),
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Checklist Items
                  if (_items.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(_items.take(6).length, (idx) {
                        final isChecked = _checkedIndices.contains(idx);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: _isList ? () => _toggleItem(idx) : null,
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isList)
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
                                          ? VoidTheme.textSecondary.withOpacity(0.35)
                                          : VoidTheme.textSecondary.withOpacity(0.85),
                                      decoration: isChecked ? TextDecoration.lineThrough : null,
                                      decorationColor: VoidTheme.textSecondary.withOpacity(0.35),
                                      height: 1.3,
                                    ),
                                    child: Text(
                                      _items[idx],
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

                  if (_items.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${_items.length - 6} outros itens',
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
