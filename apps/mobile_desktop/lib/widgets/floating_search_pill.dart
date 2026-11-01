import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/void_theme.dart';

/// Floating Search Pill component matching the user topbar aesthetic.
/// Supports programmatic focus via keyboard shortcut (e.g. '/' on desktop).
class FloatingSearchPill extends StatelessWidget {
  final bool isDesktop;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isGridView;
  final VoidCallback onToggleView;
  final VoidCallback onInvertOrder;
  final VoidCallback onMenuPressed;
  final ValueChanged<String> onChanged;

  const FloatingSearchPill({
    super.key,
    required this.isDesktop,
    required this.controller,
    required this.focusNode,
    required this.isGridView,
    required this.onToggleView,
    required this.onInvertOrder,
    required this.onMenuPressed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: VoidTheme.pillBg,
        borderRadius: BorderRadius.circular(VoidTheme.radiusPill),
        border: Border.all(color: VoidTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: VoidTheme.textPrimary, size: 22),
            onPressed: onMenuPressed,
            tooltip: 'Menu de Navegação',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: VoidTheme.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: isDesktop ? 'Search notes (Pressione "/" para focar)' : 'Search notes',
                hintStyle: TextStyle(
                  color: VoidTheme.textSecondary.withValues(alpha: 0.4),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onChanged: onChanged,
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: VoidTheme.textSecondary, size: 18),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
              tooltip: 'Limpar busca (Esc)',
            ),
          IconButton(
            icon: Icon(
              isGridView ? Icons.view_agenda_outlined : Icons.grid_view_outlined,
              color: VoidTheme.textPrimary,
              size: 20,
            ),
            onPressed: onToggleView,
            tooltip: isGridView ? 'Lista Única' : 'Grade de 2 Colunas',
          ),
          IconButton(
            icon: const Icon(Icons.swap_vert, color: VoidTheme.textPrimary, size: 22),
            onPressed: onInvertOrder,
            tooltip: 'Inverter Ordem',
          ),
          // Active dot avatar
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 4),
            decoration: const BoxDecoration(
              color: VoidTheme.accent,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'V',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: VoidTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          if (isDesktop)
            IconButton(
              icon: const Icon(Icons.close, color: VoidTheme.textSecondary, size: 18),
              onPressed: () => SystemNavigator.pop(),
              tooltip: 'Fechar (Ctrl+Q)',
            ),
        ],
      ),
    );
  }
}
