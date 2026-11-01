import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../bridge/void_bridge.dart';
import '../theme/void_theme.dart';
import '../utils/directive_parser.dart';
import '../widgets/floating_search_pill.dart';
import '../widgets/navigation_sidebar.dart';
import '../widgets/staggered_masonry_grid.dart';

/// Clean screen orchestrator coordinating bridge state, shortcuts, and decoupled child widgets.
class NotesScreen extends StatefulWidget {
  final VoidBridge bridge;

  const NotesScreen({super.key, required this.bridge});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<DirectiveNote> _allNotes = [];
  List<String> _availableDates = [];
  String _selectedDate = '';
  String _activeNavTab = 'today';
  String _searchQuery = '';

  bool _isLoading = true;
  bool _isCapturing = false;
  bool _isGridView = true;
  bool _isInverted = false;
  String _hudStatus = 'Ouvindo por "VOID"';

  Timer? _autoRefreshTimer;
  final Map<String, Set<int>> _checkedMap = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _loadDatesAndNotes();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollNotes();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
      list = list.where((n) => DirectiveParser.isChecklist(n.content)).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((n) => n.content.toLowerCase().contains(q)).toList();
    }
    if (_isInverted) {
      list = list.reversed.toList();
    }
    return list;
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
            backgroundColor: VoidTheme.accent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _onTabSelected(String tab, String? date) {
    if (tab == 'date' && date != null) {
      setState(() {
        _selectedDate = date;
        _activeNavTab = 'date';
      });
    } else {
      setState(() {
        _activeNavTab = tab;
        if (tab == 'today') {
          _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        }
      });
    }
    _pollNotes();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.slash): () {
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _searchController.clear();
          setState(() => _searchQuery = '');
          _searchFocusNode.unfocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          _pollNotes();
        },
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (!_isCapturing) _triggerManualDirective();
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 768;
            final numCols = constraints.maxWidth >= 1200
                ? 4
                : constraints.maxWidth >= 900
                    ? 3
                    : 2;

            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: VoidTheme.bg,
              drawer: isDesktop
                  ? null
                  : NavigationSidebar(
                      isDrawer: true,
                      activeTab: _activeNavTab,
                      selectedDate: _selectedDate,
                      availableDates: _availableDates,
                      hudStatus: _hudStatus,
                      onTabSelected: (tab, date) {
                        Navigator.pop(context);
                        _onTabSelected(tab, date);
                      },
                    ),
              body: SafeArea(
                child: isDesktop
                    ? Row(
                        children: [
                          NavigationSidebar(
                            isDrawer: false,
                            activeTab: _activeNavTab,
                            selectedDate: _selectedDate,
                            availableDates: _availableDates,
                            hudStatus: _hudStatus,
                            onTabSelected: _onTabSelected,
                          ),
                          const VerticalDivider(width: 1, color: VoidTheme.border),
                          Expanded(
                            child: Column(
                              children: [
                                FloatingSearchPill(
                                  isDesktop: true,
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  isGridView: _isGridView,
                                  onToggleView: () => setState(() => _isGridView = !_isGridView),
                                  onInvertOrder: () => setState(() => _isInverted = !_isInverted),
                                  onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                                  onChanged: (val) => setState(() => _searchQuery = val),
                                ),
                                Expanded(
                                  child: StaggeredMasonryGrid(
                                    notes: _filteredNotes,
                                    bridge: widget.bridge,
                                    numColumns: numCols,
                                    isGridView: _isGridView,
                                    isLoading: _isLoading,
                                    checkedMap: _checkedMap,
                                    onCheckedUpdated: (id, updated) {
                                      _checkedMap[id] = updated;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          FloatingSearchPill(
                            isDesktop: false,
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            isGridView: _isGridView,
                            onToggleView: () => setState(() => _isGridView = !_isGridView),
                            onInvertOrder: () => setState(() => _isInverted = !_isInverted),
                            onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                            onChanged: (val) => setState(() => _searchQuery = val),
                          ),
                          Expanded(
                            child: StaggeredMasonryGrid(
                              notes: _filteredNotes,
                              bridge: widget.bridge,
                              numColumns: 2,
                              isGridView: _isGridView,
                              isLoading: _isLoading,
                              checkedMap: _checkedMap,
                              onCheckedUpdated: (id, updated) {
                                _checkedMap[id] = updated;
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              floatingActionButton: _buildFab(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: VoidTheme.accent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VoidTheme.border),
        boxShadow: [
          BoxShadow(
            color: VoidTheme.accent.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(_isCapturing ? Icons.graphic_eq : Icons.add, color: VoidTheme.textPrimary, size: 28),
        onPressed: _isCapturing ? null : _triggerManualDirective,
        tooltip: 'Falar Diretiva (Ctrl+N)',
      ),
    );
  }
}
