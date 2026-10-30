import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../bridge/void_bridge.dart';

/// Main screen displaying the chronological feed of captured directives.
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

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final notes = await widget.bridge.listTodayNotes();
      setState(() {
        _notes = notes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
    await widget.bridge.triggerPriorityOverride();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Capturando diretiva por voz... Fale agora.'),
        duration: const Duration(seconds: 3),
      ),
    );
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
              'V.O.I.D.',
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
                              'Diga "Void" seguido da sua anotação.',
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
                          return Card(
                            color: const Color(0xFF1A1D27),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(color: Color(0xFF262A38)),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
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
                                  const SizedBox(height: 6),
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
