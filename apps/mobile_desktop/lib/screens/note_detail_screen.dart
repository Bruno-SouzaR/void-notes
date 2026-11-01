import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../bridge/void_bridge.dart';
import '../theme/void_theme.dart';

/// Dedicated screen for viewing and interacting with a directive note or checklist.
class NoteDetailScreen extends StatefulWidget {
  final DirectiveNote note;
  final VoidBridge bridge;
  final List<String> initialItems;
  final Set<int> initialChecked;
  final Function(Set<int>) onCheckedUpdated;

  const NoteDetailScreen({
    Key? key,
    required this.note,
    required this.bridge,
    required this.initialItems,
    required this.initialChecked,
    required this.onCheckedUpdated,
  }) : super(key: key);

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late List<String> _items;
  late Set<int> _checked;
  final TextEditingController _addItemController = TextEditingController();

  // Mapped directly to unified VoidTheme design tokens:
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

  bool get _isChecklist => _items.length > 1;

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
    if (text.isNotEmpty) {
      setState(() {
        _items.add(text);
        _addItemController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm:ss');
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: kPillBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: kPrimaryText),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isChecklist ? 'Lista de Compras' : 'Diretiva de Voz',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kPrimaryText),
            ),
            Text(
              '${dateFormat.format(widget.note.createdAt)} às ${timeFormat.format(widget.note.createdAt)}',
              style: TextStyle(fontSize: 11, color: kSecondaryText.withOpacity(0.6)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: kPrimaryText),
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
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress Header Card (if checklist)
            if (_isChecklist)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: kMenuSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '🛒 LISTA ATIVA',
                            style: TextStyle(
                              color: kPrimaryText,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(_progress * 100).toInt()}% concluído',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _progress == 1.0 ? Colors.greenAccent : kPrimaryText,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 6,
                        backgroundColor: kPillBg,
                        valueColor: const AlwaysStoppedAnimation<Color>(kAccent),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_checked.length} de ${_items.length} itens marcados',
                      style: TextStyle(fontSize: 12, color: kSecondaryText.withOpacity(0.65)),
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
                              color: isChecked ? kSecondaryText.withOpacity(0.35) : kPrimaryText,
                              fontSize: 15,
                              decoration: isChecked ? TextDecoration.lineThrough : null,
                              decorationColor: kSecondaryText.withOpacity(0.35),
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
                        hintStyle: TextStyle(color: kSecondaryText.withOpacity(0.4), fontSize: 13),
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
                          borderSide: const BorderSide(color: kAccent, width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) => _addItem(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: kAccent, size: 34),
                    tooltip: 'Adicionar',
                    onPressed: _addItem,
                  ),
                ],
              ),
            ] else ...[
              // Free-form note presentation
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
                  style: const TextStyle(
                    color: kPrimaryText,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Metadata & Audio Diagnostics Box
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
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: kSecondaryText.withOpacity(0.5)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Duração do Áudio: ${(widget.note.audioDurationMs / 1000).toStringAsFixed(1)}s gravados',
                    style: TextStyle(fontSize: 12, color: kSecondaryText.withOpacity(0.8), fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Identificador Único: ${widget.note.id}',
                    style: TextStyle(fontSize: 12, color: kSecondaryText.withOpacity(0.8), fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Transcrição Bruta: "${widget.note.rawTranscription}"',
                    style: TextStyle(fontSize: 12, color: kSecondaryText.withOpacity(0.5), fontStyle: FontStyle.italic),
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
