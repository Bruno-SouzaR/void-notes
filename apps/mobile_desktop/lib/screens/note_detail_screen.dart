import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../bridge/void_bridge.dart';
import '../theme/void_theme.dart';
import '../utils/directive_parser.dart';

/// Dedicated screen for viewing and interacting with a directive note or checklist.
class NoteDetailScreen extends StatefulWidget {
  final DirectiveNote note;
  final VoidBridge bridge;
  final List<String> initialItems;
  final Set<int> initialChecked;
  final Function(Set<int>) onCheckedUpdated;

  const NoteDetailScreen({
    super.key,
    required this.note,
    required this.bridge,
    required this.initialItems,
    required this.initialChecked,
    required this.onCheckedUpdated,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late List<String> _items;
  late Set<int> _checked;
  final TextEditingController _addItemController = TextEditingController();

  static const Color kBgColor = VoidTheme.bg;
  static const Color kPillBg = VoidTheme.pillBg;
  static const Color kMenuSurface = VoidTheme.surface;
  static const Color kAccent = VoidTheme.accent;
  static const Color kInactiveDot = VoidTheme.inactiveDot;
  static const Color kPrimaryText = VoidTheme.textPrimary;
  static const Color kSecondaryText = VoidTheme.textSecondary;
  static const Color kBorder = VoidTheme.border;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    _checked = Set.from(widget.initialChecked);
  }

  @override
  void dispose() {
    _addItemController.dispose();
    super.dispose();
  }

  bool get _isChecklist => DirectiveParser.isChecklist(widget.note.content);

  double get _progress => _items.isEmpty ? 0.0 : _checked.length / _items.length;

  void _toggleCheck(int index) {
    setState(() {
      if (_checked.contains(index)) {
        _checked.remove(index);
      } else {
        _checked.add(index);
      }
    });
    widget.onCheckedUpdated(_checked);
  }

  void _addItem() {
    final text = _addItemController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(text);
      _addItemController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd \'de\' MMMM \'de\' yyyy', 'pt_BR');
    final timeFormat = DateFormat('HH:mm');

    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: kPillBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isChecklist ? 'Lista de Compras' : 'Diretiva de Voz',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kPrimaryText),
            ),
            Text(
              '${dateFormat.format(widget.note.createdAt)} às ${timeFormat.format(widget.note.createdAt)}',
              style: TextStyle(fontSize: 11, color: kSecondaryText.withValues(alpha: 0.5)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: kAccent),
            tooltip: 'Copiar texto',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.note.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Nota copiada para a área de transferência!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.undo, size: 20, color: Colors.orangeAccent),
            tooltip: 'Revogar diretiva',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kMenuSurface,
                  title: const Text('Revogar Nota?', style: TextStyle(color: kPrimaryText)),
                  content: const Text(
                    'Esta diretiva será removida do histórico e marcada como cancelada.',
                    style: TextStyle(color: kSecondaryText),
                  ),
                  actions: [
                    TextButton(
                      child: const Text('Cancelar', style: TextStyle(color: kSecondaryText)),
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      child: const Text('Revogar'),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await widget.bridge.revokeLatestDirective();
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isChecklist)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kMenuSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: kAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: kAccent),
                              ),
                              child: const Text(
                                'PROGRESSO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: kPrimaryText,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(_progress * 100).toInt()}% concluído',
                              style: const TextStyle(fontSize: 13, color: kPrimaryText),
                            ),
                          ],
                        ),
                        Text(
                          '${_checked.length}/${_items.length}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _progress == 1.0 ? VoidTheme.success : kAccent,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 6,
                        backgroundColor: kPillBg,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _progress == 1.0 ? VoidTheme.success : kAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_checked.length} de ${_items.length} itens marcados',
                      style: TextStyle(fontSize: 12, color: kSecondaryText.withValues(alpha: 0.65)),
                    ),
                  ],
                ),
              ),

            // Content Section
            if (_isChecklist) ...[
              const Text(
                'ITENS DA LISTA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: kPrimaryText,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: kMenuSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  children: List.generate(_items.length, (idx) {
                    final isChecked = _checked.contains(idx);
                    return Column(
                      children: [
                        ListTile(
                          onTap: () => _toggleCheck(idx),
                          leading: Icon(
                            isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                            color: isChecked ? kAccent : kInactiveDot,
                            size: 22,
                          ),
                          title: Text(
                            _items[idx],
                            style: TextStyle(
                              color: isChecked ? kSecondaryText.withValues(alpha: 0.35) : kPrimaryText,
                              fontSize: 15,
                              decoration: isChecked ? TextDecoration.lineThrough : null,
                              decorationColor: kSecondaryText.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                        if (idx < _items.length - 1)
                          const Divider(color: kPillBg, height: 1),
                      ],
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),
              // Add Item Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addItemController,
                      style: const TextStyle(color: kPrimaryText, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Adicionar item manual...',
                        hintStyle: TextStyle(color: kSecondaryText.withValues(alpha: 0.4), fontSize: 13),
                        filled: true,
                        fillColor: kPillBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: kBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: kBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: kAccent),
                        ),
                      ),
                      onSubmitted: (_) => _addItem(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: kAccent, size: 32),
                    onPressed: _addItem,
                    tooltip: 'Adicionar à lista',
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: kMenuSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Text(
                  widget.note.content,
                  style: const TextStyle(fontSize: 16, height: 1.5, color: kPrimaryText),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Metadata Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kPillBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DETALHES DA CAPTURA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: kSecondaryText.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Duração do Áudio: ${(widget.note.audioDurationMs / 1000).toStringAsFixed(1)}s gravados',
                    style: TextStyle(fontSize: 12, color: kSecondaryText.withValues(alpha: 0.8), fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Identificador Único: ${widget.note.id}',
                    style: TextStyle(fontSize: 12, color: kSecondaryText.withValues(alpha: 0.8), fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Transcrição Bruta: "${widget.note.rawTranscription}"',
                    style: TextStyle(fontSize: 12, color: kSecondaryText.withValues(alpha: 0.5), fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
