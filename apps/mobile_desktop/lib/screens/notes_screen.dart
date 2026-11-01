import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../bridge/void_bridge.dart';

/// Main adaptive screen providing split-view for Desktop and thumb-friendly flow for Mobile.
class NotesScreen extends StatefulWidget {
  final VoidBridge bridge;

  const NotesScreen({Key? key, required this.bridge}) : super(key: key);

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<DirectiveNote> _allNotes = [];
  List<String> _availableDates = [];
  String _selectedDate = '';
  String _activeNavTab = 'today'; // 'today', 'lists', 'all', or date
  String _searchQuery = '';

  bool _isLoading = true;
  bool _silentMode = false;
  bool _isCapturing = false;
  String _selectedModel = 'small';
  String _hudStatus = 'Ouvindo por "VOID"';

  Timer? _autoRefreshTimer;
  final Map<String, Set<int>> _checkedItems = {};

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.bridge.selectedModel;
    _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _loadDatesAndNotes();

    // Auto-refresh every 3s to reflect notes captured by background daemon
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollNotes();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDatesAndNotes() async {
    setState(() => _isLoading = true);
    try {
      final dates = await widget.bridge.listAvailableDates();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (!dates.contains(todayStr)) {
        dates.insert(0, todayStr);
      }
      _availableDates = dates;
      if (_selectedDate.isEmpty) {
        _selectedDate = todayStr;
      }
    } catch (_) {}
    await _pollNotes();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pollNotes() async {
    try {
      List<DirectiveNote> notes;
      if (_activeNavTab == 'all') {
        notes = [];
        for (final d in _availableDates.take(7)) {
          final dayNotes = await widget.bridge.listNotesForDate(d);
          notes.addAll(dayNotes);
        }
      } else {
        notes = await widget.bridge.listNotesForDate(_selectedDate);
      }

      if (mounted) {
        setState(() {
          _allNotes = notes;
        });
      }
    } catch (_) {}
  }

  List<DirectiveNote> get _filteredNotes {
    var list = _allNotes;
    if (_activeNavTab == 'lists') {
      list = list.where((n) => _isChecklist(n.content)).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((n) => n.content.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  Future<void> _toggleSilentMode(bool value) async {
    await widget.bridge.setSilentMode(value);
    setState(() => _silentMode = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Modo Silencioso Ativado (Chimes mutados)'
              : 'Modo Normal Ativado (Chimes ativos)',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _triggerManualDirective() async {
    setState(() {
      _isCapturing = true;
      _hudStatus = 'Gravando fala... (5s)';
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎙️ Gravando por 5s... Fale no microfone agora.'),
        duration: Duration(seconds: 5),
      ),
    );

    final countBefore = _allNotes.length;
    await widget.bridge.triggerPriorityOverride();
    setState(() => _hudStatus = 'Transcrevendo Whisper...');
    await _pollNotes();

    if (mounted) {
      setState(() {
        _isCapturing = false;
        _hudStatus = 'Ouvindo por "VOID"';
      });

      final countAfter = _allNotes.length;
      if (countAfter > countBefore) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Nota capturada: "${_allNotes.first.content}"'),
            backgroundColor: Colors.teal.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _revokeLatest() async {
    final revoked = await widget.bridge.revokeLatestDirective();
    if (revoked != null) {
      await _loadDatesAndNotes();
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
        lower.contains('mercado') ||
        lower.contains('comprar') ||
        content.contains('- [ ]') ||
        content.contains('- [x]');
  }

  List<String> _extractItems(String content) {
    if (content.contains('\n')) {
      return content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    }
    if (content.contains(':')) {
      final afterColon = content.split(':').sublist(1).join(':').trim();
      return afterColon.split(',').map((i) => i.trim()).where((i) => i.isNotEmpty).toList();
    }
    return [content];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;
        return Scaffold(
          backgroundColor: const Color(0xFF0A0D14), // Deep OLED black
          appBar: _buildAppBar(isDesktop),
          body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
          bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF06B6D4), // Cyan Accent
            foregroundColor: Colors.black,
            elevation: 4,
            icon: const Icon(Icons.mic, size: 22),
            label: Text(
              _isCapturing ? 'Ouvindo...' : 'Falar Diretiva',
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            onPressed: _isCapturing ? null : _triggerManualDirective,
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDesktop) {
    return AppBar(
      backgroundColor: const Color(0xFF121622),
      elevation: 0,
      titleSpacing: isDesktop ? 24 : 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF06B6D4).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.4)),
            ),
            child: const Text(
              'VOID',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
                fontSize: 14,
                color: Color(0xFF22D3EE),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'notes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w300,
              color: Colors.white70,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
      actions: [
        // Model Selector Dropdown
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2030),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF263045)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedModel,
              dropdownColor: const Color(0xFF161C2A),
              style: const TextStyle(fontSize: 12, color: Color(0xFF22D3EE), fontWeight: FontWeight.bold),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF22D3EE), size: 18),
              items: const [
                DropdownMenuItem(value: 'small', child: Text('Small (181 MB)')),
                DropdownMenuItem(value: 'base', child: Text('Base (57 MB)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedModel = val);
                  widget.bridge.setSelectedModel(val);
                }
              },
            ),
          ),
        ),

        // Silent / Meeting Mode Switch
        Row(
          children: [
            Icon(
              _silentMode ? Icons.volume_off : Icons.volume_up,
              size: 18,
              color: _silentMode ? Colors.amber : Colors.white38,
            ),
            Switch(
              value: _silentMode,
              onChanged: _toggleSilentMode,
              activeColor: Colors.amber,
            ),
          ],
        ),

        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: 'Atualizar notas',
          onPressed: _loadDatesAndNotes,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // Desktop Split-View: Sidebar + Main Content Feed
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Navigation Sidebar
        Container(
          width: 260,
          color: const Color(0xFF0E121C),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildSidebarItem(
                id: 'today',
                icon: Icons.today,
                label: 'Hoje',
                badge: _availableDates.isNotEmpty && _availableDates.first == _selectedDate
                    ? '${_allNotes.length}'
                    : null,
              ),
              _buildSidebarItem(
                id: 'lists',
                icon: Icons.checklist_rtl,
                label: 'Listas & Compras',
                badge: '${_allNotes.where((n) => _isChecklist(n.content)).length}',
              ),
              _buildSidebarItem(
                id: 'all',
                icon: Icons.auto_awesome_motion,
                label: 'Todas as Notas',
              ),
              const Divider(color: Color(0xFF1E2536), height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'HISTÓRICO DE DATAS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _availableDates.length,
                  itemBuilder: (context, idx) {
                    final d = _availableDates[idx];
                    final isSelected = _selectedDate == d && _activeNavTab != 'all' && _activeNavTab != 'lists';
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: isSelected ? const Color(0xFF22D3EE) : Colors.white24,
                      ),
                      title: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: isSelected ? Colors.white : Colors.white60,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedTileColor: const Color(0xFF161E2E),
                      onTap: () {
                        setState(() {
                          _selectedDate = d;
                          _activeNavTab = 'date';
                        });
                        _pollNotes();
                      },
                    );
                  },
                ),
              ),
              // System health badge at bottom
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141926),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E2536)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.graphic_eq, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PipeWire • Whisper 2T • CPU <1%',
                        style: TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Vertical divider
        const VerticalDivider(width: 1, color: Color(0xFF1E2536)),

        // Main Feed
        Expanded(
          child: Column(
            children: [
              _buildSearchBar(),
              _buildVoiceHudBar(),
              Expanded(child: _buildFeedView()),
            ],
          ),
        ),
      ],
    );
  }

  // Mobile Single Column Layout with Safe Area
  Widget _buildMobileLayout() {
    return SafeArea(
      child: Column(
        children: [
          _buildSearchBar(),
          _buildVoiceHudBar(),
          Expanded(child: _buildFeedView()),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar() {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFF121622),
      selectedItemColor: const Color(0xFF22D3EE),
      unselectedItemColor: Colors.white38,
      currentIndex: _activeNavTab == 'today' ? 0 : (_activeNavTab == 'lists' ? 1 : 2),
      onTap: (idx) {
        setState(() {
          if (idx == 0) {
            _activeNavTab = 'today';
            _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
          } else if (idx == 1) {
            _activeNavTab = 'lists';
          } else {
            _activeNavTab = 'all';
          }
        });
        _pollNotes();
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.today), label: 'Hoje'),
        BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Listas'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Histórico'),
      ],
    );
  }

  Widget _buildSidebarItem({
    required String id,
    required IconData icon,
    required String label,
    String? badge,
  }) {
    final isSelected = _activeNavTab == id;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, size: 18, color: isSelected ? const Color(0xFF22D3EE) : Colors.white54),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: badge != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF06B6D4) : const Color(0xFF1E2536),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      selected: isSelected,
      selectedTileColor: const Color(0xFF161E2E),
      onTap: () {
        setState(() {
          _activeNavTab = id;
          if (id == 'today') {
            _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
          }
        });
        _pollNotes();
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0A0D14),
      child: TextField(
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Buscar diretivas, itens de mercado ou tarefas...',
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: Colors.white38),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF121622),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
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
        onChanged: (val) => setState(() => _searchQuery = val),
      ),
    );
  }

  Widget _buildVoiceHudBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF121622),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isCapturing ? Colors.redAccent : const Color(0xFF10B981),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_isCapturing ? Colors.redAccent : const Color(0xFF10B981)).withOpacity(0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _hudStatus,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const Spacer(),
          if (_allNotes.isNotEmpty)
            TextButton.icon(
              onPressed: _revokeLatest,
              icon: const Icon(Icons.undo, size: 13, color: Colors.white60),
              label: const Text(
                'Desfazer última',
                style: TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4)));
    }

    final notes = _filteredNotes;

    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_none, size: 48, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Nenhuma diretiva encontrada para "$_searchQuery".'
                  : 'Nenhuma anotação nesta seção.',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Diga "VOID" no microfone ou clique em "Falar Diretiva".',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final timeFormat = DateFormat('HH:mm:ss');

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final isList = _isChecklist(note.content);
        final checkedSet = _checkedItems.putIfAbsent(note.id, () => <int>{});
        final items = isList ? _extractItems(note.content) : <String>[];
        final totalItems = items.length;
        final completedCount = checkedSet.length;
        final progress = totalItems > 0 ? (completedCount / totalItems) : 0.0;

        return Card(
          color: const Color(0xFF141926),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isList ? const Color(0xFF06B6D4).withOpacity(0.3) : const Color(0xFF1E2536),
            ),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Meta Row
                Row(
                  children: [
                    if (isList)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LISTA DE COMPRAS',
                          style: TextStyle(
                            color: Color(0xFF22D3EE),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Text(
                      timeFormat.format(note.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF22D3EE),
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Copy text button
                    IconButton(
                      icon: const Icon(Icons.copy, size: 14, color: Colors.white38),
                      tooltip: 'Copiar texto',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: note.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copiado para a área de transferência!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Checklist Render with Progress
                if (isList && items.length > 1) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: const Color(0xFF1E2536),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$completedCount de $totalItems itens marcados (${(progress * 100).toInt()}%)',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                  const SizedBox(height: 6),
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
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(
                                isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                                size: 18,
                                color: isChecked ? const Color(0xFF10B981) : Colors.white38,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  items[itemIdx],
                                  style: TextStyle(
                                    color: isChecked ? Colors.white38 : Colors.white,
                                    fontSize: 13,
                                    decoration: isChecked ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ] else ...[
                  Text(
                    note.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
