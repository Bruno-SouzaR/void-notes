import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../bridge/void_bridge.dart';
import 'note_detail_screen.dart';

/// Staggered Masonry Grid screen inspired by Google Keep and Apple Notes.
class NotesScreen extends StatefulWidget {
  final VoidBridge bridge;

  const NotesScreen({Key? key, required this.bridge}) : super(key: key);

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<DirectiveNote> _allNotes = [];
  List<String> _availableDates = [];
  String _selectedDate = '';
  String _activeNavTab = 'today'; // 'today', 'lists', 'all', or date
  String _searchQuery = '';

  bool _isLoading = true;
  bool _silentMode = false;
  bool _isCapturing = false;
  bool _isGridView = true; // Toggle between 2-column grid and single-column list
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

  bool _isChecklist(String content) {
    final lower = content.toLowerCase();
    return lower.contains('lista') ||
        lower.contains('mercado') ||
        lower.contains('compras') ||
        lower.contains('comprar') ||
        content.contains('- [ ]') ||
        content.contains('- [x]');
  }

  (String title, List<String> items, bool isList) _parseNoteStructure(DirectiveNote note) {
    var text = note.content.trim();
    final lower = text.toLowerCase();
    final isList = _isChecklist(text);

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFF101216), // Dark background matching screenshot
          drawer: _buildDrawer(),
          body: SafeArea(
            child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
          ),
          floatingActionButton: _buildFab(),
        );
      },
    );
  }

  Widget _buildFab() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF0084FF), // Vivid blue matching screenshot
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0084FF).withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(_isCapturing ? Icons.graphic_eq : Icons.add, color: Colors.white, size: 28),
        onPressed: _isCapturing ? null : _triggerManualDirective,
        tooltip: 'Falar Diretiva',
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF14171E),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1E2128)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0084FF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'VOID',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 2.0,
                          color: Color(0xFF0084FF),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('notes', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _hudStatus,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.today, color: Colors.white70),
            title: const Text('Hoje', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _activeNavTab = 'today';
                _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
              });
              _pollNotes();
            },
          ),
          ListTile(
            leading: const Icon(Icons.checklist, color: Colors.white70),
            title: const Text('Listas de Compras', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _activeNavTab = 'lists');
              _pollNotes();
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_motion, color: Colors.white70),
            title: const Text('Todas as Notas', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _activeNavTab = 'all');
              _pollNotes();
            },
          ),
          const Divider(color: Color(0xFF262A34)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('HISTÓRICO', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          ..._availableDates.map((d) {
            final isSelected = _selectedDate == d && _activeNavTab != 'all' && _activeNavTab != 'lists';
            return ListTile(
              dense: true,
              leading: Icon(Icons.calendar_today, size: 14, color: isSelected ? const Color(0xFF0084FF) : Colors.white24),
              title: Text(d, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 12, fontFamily: 'monospace')),
              selected: isSelected,
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedDate = d;
                  _activeNavTab = 'date';
                });
                _pollNotes();
              },
            );
          }),
        ],
      ),
    );
  }

  // Floating White Search Pill matching screenshot
  Widget _buildFloatingSearchPill(bool isDesktop) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white, // Crisp white pill like in screenshot
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFF2D3139), size: 22),
            onPressed: () {
              _scaffoldKey.currentState?.openDrawer();
            },
            tooltip: 'Menu de Navegação',
          ),
          Expanded(
            child: TextField(
              style: const TextStyle(color: Color(0xFF1E2128), fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Search notes',
                hintStyle: TextStyle(color: Color(0xFF8E95A5), fontSize: 15),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_agenda_outlined : Icons.grid_view_outlined,
              color: const Color(0xFF2D3139),
              size: 20,
            ),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? 'Lista Única' : 'Grade de 2 Colunas',
          ),
          IconButton(
            icon: const Icon(Icons.swap_vert, color: Color(0xFF2D3139), size: 22),
            onPressed: () {
              setState(() {
                _allNotes = _allNotes.reversed.toList();
              });
            },
            tooltip: 'Inverter Ordem',
          ),
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF0084FF),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'V',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mobile Single Column / 2-Column Grid
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildFloatingSearchPill(false),
        Expanded(child: _buildStaggeredGrid(2)),
      ],
    );
  }

  // Desktop Responsive Layout
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar
        Container(
          width: 240,
          color: const Color(0xFF14171E),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildSidebarItem('today', Icons.today, 'Hoje'),
              _buildSidebarItem('lists', Icons.checklist, 'Listas & Compras'),
              _buildSidebarItem('all', Icons.auto_awesome_motion, 'Todas as Notas'),
              const Divider(color: Color(0xFF262A34), height: 24),
              Expanded(
                child: ListView(
                  children: _availableDates.map((d) {
                    final isSelected = _selectedDate == d && _activeNavTab != 'all' && _activeNavTab != 'lists';
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.calendar_today, size: 14, color: isSelected ? const Color(0xFF0084FF) : Colors.white24),
                      title: Text(d, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 12, fontFamily: 'monospace')),
                      selected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedDate = d;
                          _activeNavTab = 'date';
                        });
                        _pollNotes();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF262A34)),
        Expanded(
          child: Column(
            children: [
              _buildFloatingSearchPill(true),
              Expanded(child: _buildStaggeredGrid(3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarItem(String id, IconData icon, String label) {
    final isSelected = _activeNavTab == id;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: isSelected ? const Color(0xFF0084FF) : Colors.white54, size: 20),
      title: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
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

  // Staggered Masonry Grid Implementation
  Widget _buildStaggeredGrid(int numCols) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0084FF)));
    }

    final notes = _filteredNotes;
    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.notes, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text('Nenhuma nota encontrada.', style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      );
    }

    if (!_isGridView) {
      // Single Column List Mode
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: notes.length,
        itemBuilder: (context, idx) => _buildStaggeredCard(notes[idx]),
      );
    }

    // Distribute into N columns for Masonry layout
    final columns = List.generate(numCols, (_) => <Widget>[]);
    for (var i = 0; i < notes.length; i++) {
      columns[i % numCols].add(_buildStaggeredCard(notes[i]));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(numCols, (colIdx) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: colIdx == 0 ? 0 : 6,
                right: colIdx == numCols - 1 ? 0 : 6,
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

  // Individual Card matching the screenshot style
  Widget _buildStaggeredCard(DirectiveNote note) {
    final (title, items, isList) = _parseNoteStructure(note);
    final checkedSet = _checkedItems.putIfAbsent(note.id, () => <int>{});
    final totalItems = items.length;
    final checkedCount = checkedSet.length;
    final progress = totalItems > 0 ? (checkedCount / totalItems) : 0.0;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoteDetailScreen(
              note: note,
              bridge: widget.bridge,
              initialItems: items.isNotEmpty ? items : [note.content],
              initialChecked: checkedSet,
              onCheckedUpdated: (updated) {
                setState(() {
                  _checkedItems[note.id] = updated;
                });
              },
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2128), // Matte Dark Charcoal matching the reference screenshot
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title in bold white
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),

            // Progress bar (if checklist with > 1 item)
            if (isList && totalItems > 1) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: const Color(0xFF2C303B),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress == 1.0 ? const Color(0xFF10B981) : const Color(0xFF0084FF),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$checkedCount de $totalItems (${(progress * 100).toInt()}%)',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8E95A5), fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
            ],

            // Items preview (up to 6 items displayed)
            if (items.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(items.take(6).length, (idx) {
                  final isChecked = checkedSet.contains(idx);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isList)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 6),
                            child: Icon(
                              isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                              size: 14,
                              color: isChecked ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            items[idx],
                            style: TextStyle(
                              fontSize: 13,
                              color: isChecked ? const Color(0xFF6B7280) : const Color(0xFF9E9E9E),
                              decoration: isChecked ? TextDecoration.lineThrough : null,
                              decorationColor: const Color(0xFF6B7280),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),

            if (items.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ ${items.length - 6} outros itens',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF60A5FA)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
