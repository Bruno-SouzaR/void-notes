import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../bridge/void_bridge.dart';

/// Main screen displaying the chronological feed of captured directives and checklist cards.
class NotesScreen extends StatefulWidget {
  final VoidBridge bridge;

  const NotesScreen({Key? key, required this.bridge}) : super(key: key);

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<DirectiveNote> _notes = [];
  bool _isLoading = true;
  bool _silentMode = false;
  bool _isCapturing = false;
  String _selectedModel = 'base';
  Timer? _autoRefreshTimer;
  final Map<String, Set<int>> _checkedItems = {};

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.bridge.selectedModel;
    _loadNotes();
    // Auto-refresh every 3 seconds to reflect notes captured in background
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollNotes();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    await _pollNotes();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pollNotes() async {
    try {
      final notes = await widget.bridge.listTodayNotes();
      if (mounted) {
        setState(() {
          _notes = notes;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleSilentMode(bool value) async {
    await widget.bridge.setSilentMode(value);
    setState(() => _silentMode = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Modo Silencioso / Reunião Ativado (Chimes mutados)'
              : 'Modo Normal Ativado (Chimes ativos)',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _triggerManualDirective() async {
    setState(() => _isCapturing = true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎙️ Gravando por 5s... Fale no microfone agora.'),
        duration: Duration(seconds: 5),
      ),
    );

    final countBefore = _notes.length;
    await widget.bridge.triggerPriorityOverride();
    await _pollNotes();

    if (mounted) {
      setState(() => _isCapturing = false);
      final countAfter = _notes.length;
      if (countAfter > countBefore) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Nota capturada: "${_notes.first.content}"'),
            backgroundColor: Colors.teal.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Nenhuma fala audível detectada. Tente falar mais perto do microfone.'),
            backgroundColor: Colors.deepOrange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _revokeLatest() async {
    final revoked = await widget.bridge.revokeLatestDirective();
    if (revoked != null) {
      await _loadNotes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Diretiva revogada: "${revoked.content}"'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  bool _isChecklist(String content) {
    final lower = content.toLowerCase();
    return lower.contains('lista') ||
        lower.contains('compras') ||
        lower.contains('mercado') ||
        content.contains('- [ ]') ||
        content.contains('- [x]');
  }

  List<String> _extractItems(String content) {
    if (content.contains('\n')) {
      return content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    }
    // If separated by commas or colons
    if (content.contains(':')) {
      final afterColon = content.split(':').sublist(1).join(':').trim();
      return afterColon.split(',').map((i) => i.trim()).where((i) => i.isNotEmpty).toList();
    }
    return [content];
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm:ss');
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161922),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'void-notes',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            Text(
              'Diretivas Diárias — ${dateFormat.format(DateTime.now())}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2230),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF262A38)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedModel,
                dropdownColor: const Color(0xFF1A1D27),
                style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent, size: 18),
                items: const [
                  DropdownMenuItem(
                    value: 'base',
                    child: Text('Base (57 MB)'),
                  ),
                  DropdownMenuItem(
                    value: 'small',
                    child: Text('Small (181 MB)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedModel = val);
                    widget.bridge.setSelectedModel(val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          val == 'small'
                              ? 'Modelo Small ativado (Alta precisão para fala rápida)'
                              : 'Modelo Base ativado (Ultra-leve)',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          Row(
            children: [
              Icon(
                _silentMode ? Icons.volume_off : Icons.volume_up,
                size: 20,
                color: _silentMode ? Colors.amber : Colors.grey,
              ),
              const SizedBox(width: 4),
              Switch(
                value: _silentMode,
                onChanged: _toggleSilentMode,
                activeColor: Colors.amber,
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotes,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Listening status banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF1E2230),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isCapturing ? Colors.redAccent : Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isCapturing
                      ? 'Gravando diretiva...'
                      : 'Ouvindo em background por "Void"',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const Spacer(),
                if (_notes.isNotEmpty)
                  TextButton.icon(
                    onPressed: _revokeLatest,
                    icon: const Icon(Icons.undo, size: 14, color: Colors.white70),
                    label: const Text(
                      'Desfazer',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.mic_none, size: 48, color: Colors.white24),
                            SizedBox(height: 16),
                            Text(
                              'Nenhuma diretiva registrada hoje.',
                              style: TextStyle(color: Colors.white54, fontSize: 14),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Diga "Void" seguido da sua anotação ou clique no botão abaixo.',
                              style: TextStyle(color: Colors.white24, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _notes.length,
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          final isList = _isChecklist(note.content);
                          final checkedSet = _checkedItems.putIfAbsent(note.id, () => <int>{});
                          final items = isList ? _extractItems(note.content) : <String>[];

                          return Card(
                            color: const Color(0xFF1A1D27),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isList ? Colors.cyan.withOpacity(0.3) : const Color(0xFF262A38),
                              ),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (isList)
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.cyan.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'LISTA DE COMPRAS',
                                            style: TextStyle(
                                              color: Colors.cyanAccent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        timeFormat.format(note.createdAt),
                                        style: const TextStyle(
                                          color: Colors.cyanAccent,
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${(note.audioDurationMs / 1000).toStringAsFixed(1)}s',
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (isList && items.length > 1)
                                    Column(
                                      children: List.generate(items.length, (itemIdx) {
                                        final isChecked = checkedSet.contains(itemIdx);
                                        return InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (isChecked) {
                                                checkedSet.remove(itemIdx);
                                              } else {
                                                checkedSet.add(itemIdx);
                                              }
                                            });
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isChecked
                                                      ? Icons.check_box
                                                      : Icons.check_box_outline_blank,
                                                  size: 18,
                                                  color: isChecked ? Colors.cyanAccent : Colors.white38,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    items[itemIdx],
                                                    style: TextStyle(
                                                      color: isChecked ? Colors.white38 : Colors.white,
                                                      fontSize: 13,
                                                      decoration: isChecked
                                                          ? TextDecoration.lineThrough
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    )
                                  else
                                    Text(
                                      note.content,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.cyanAccent.shade700,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.mic),
        label: const Text('Falar Diretiva'),
        onPressed: _triggerManualDirective,
      ),
    );
  }
}
