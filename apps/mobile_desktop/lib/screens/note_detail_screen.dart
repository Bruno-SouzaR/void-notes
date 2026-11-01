import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../bridge/void_bridge.dart';

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
      backgroundColor: const Color(0xFF0A0D14), // Deep OLED black
      appBar: AppBar(
        backgroundColor: const Color(0xFF121622),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isChecklist ? 'Lista de Compras' : 'Diretiva de Voz',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              '${dateFormat.format(widget.note.createdAt)} às ${timeFormat.format(widget.note.createdAt)}',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: Color(0xFF22D3EE)),
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
                  color: const Color(0xFF141926),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '🛒 LISTA ATIVA',
                            style: TextStyle(
                              color: Color(0xFF22D3EE),
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
                            color: _progress == 1.0 ? const Color(0xFF10B981) : const Color(0xFF22D3EE),
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
                        minHeight: 8,
                        backgroundColor: const Color(0xFF1E2536),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _progress == 1.0 ? const Color(0xFF10B981) : const Color(0xFF06B6D4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_checked.length} de ${_items.length} itens marcados',
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
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
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF121622),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E2536)),
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
                            color: isChecked ? const Color(0xFF10B981) : Colors.white38,
                            size: 22,
                          ),
                          title: Text(
                            _items[idx],
                            style: TextStyle(
                              color: isChecked ? Colors.white38 : Colors.white,
                              fontSize: 15,
                              decoration: isChecked ? TextDecoration.lineThrough : null,
                              decorationColor: Colors.white38,
                            ),
                          ),
                        ),
                        if (idx < _items.length - 1)
                          const Divider(color: Color(0xFF1A2030), height: 1),
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
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Adicionar item manual...',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF121622),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF1E2536)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF1E2536)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF06B6D4)),
                        ),
                      ),
                      onSubmitted: (_) => _addItem(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF06B6D4), size: 32),
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
                  color: const Color(0xFF141926),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E2536)),
                ),
                child: Text(
                  widget.note.content,
                  style: const TextStyle(
                    color: Colors.white,
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0E121A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF181E2B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DETALHES DA CAPTURA',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white38),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Duração do Áudio: ${(widget.note.audioDurationMs / 1000).toStringAsFixed(1)}s gravados',
                    style: const TextStyle(fontSize: 12, color: Colors.white54, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Identificador Único: ${widget.note.id}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Transcrição Bruta: "${widget.note.rawTranscription}"',
                    style: const TextStyle(fontSize: 12, color: Colors.white38, fontStyle: FontStyle.italic),
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
