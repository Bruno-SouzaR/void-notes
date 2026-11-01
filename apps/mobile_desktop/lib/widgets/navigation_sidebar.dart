import 'package:flutter/material.dart';
import '../theme/void_theme.dart';

/// Navigation sidebar used both in Desktop split-view and Mobile Drawer.
class NavigationSidebar extends StatelessWidget {
  final bool isDrawer;
  final String activeTab;
  final String selectedDate;
  final List<String> availableDates;
  final String hudStatus;
  final Function(String tab, String? date) onTabSelected;

  const NavigationSidebar({
    Key? key,
    required this.isDrawer,
    required this.activeTab,
    required this.selectedDate,
    required this.availableDates,
    required this.hudStatus,
    required this.onTabSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (isDrawer)
          DrawerHeader(
            decoration: const BoxDecoration(
              color: VoidTheme.surface,
              border: Border(bottom: BorderSide(color: VoidTheme.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: VoidTheme.accent,
                        borderRadius: BorderRadius.circular(VoidTheme.radiusSmall),
                      ),
                      child: const Text(
                        'VOID',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 2.0,
                          color: VoidTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('notes', style: TextStyle(color: VoidTheme.textPrimary, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  hudStatus,
                  style: TextStyle(color: VoidTheme.textSecondary.withOpacity(0.6), fontSize: 12),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: VoidTheme.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: VoidTheme.accent,
                    borderRadius: BorderRadius.circular(VoidTheme.radiusSmall),
                  ),
                  child: const Text(
                    'VOID',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 1.5,
                      color: VoidTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('notes', style: TextStyle(color: VoidTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _buildItem('today', Icons.today, 'Hoje'),
        _buildItem('lists', Icons.checklist, 'Listas & Compras'),
        _buildItem('all', Icons.auto_awesome_motion, 'Todas as Notas'),
        const Divider(color: VoidTheme.border, height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'HISTÓRICO',
              style: TextStyle(
                color: VoidTheme.textSecondary.withOpacity(0.5),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: availableDates.map((d) {
              final isSelected = selectedDate == d && activeTab != 'all' && activeTab != 'lists';
              return ListTile(
                dense: true,
                leading: Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: isSelected ? VoidTheme.accent : VoidTheme.inactiveDot,
                ),
                title: Text(
                  d,
                  style: TextStyle(
                    color: isSelected ? VoidTheme.textPrimary : VoidTheme.textSecondary.withOpacity(0.6),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                selected: isSelected,
                selectedTileColor: VoidTheme.surface,
                onTap: () => onTabSelected('date', d),
              );
            }).toList(),
          ),
        ),
      ],
    );

    if (isDrawer) {
      return Drawer(
        backgroundColor: VoidTheme.pillBg,
        child: content,
      );
    }

    return Container(
      width: 240,
      color: VoidTheme.pillBg,
      child: content,
    );
  }

  Widget _buildItem(String id, IconData icon, String label) {
    final isSelected = activeTab == id;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: isSelected ? VoidTheme.accent : VoidTheme.inactiveDot, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? VoidTheme.textPrimary : VoidTheme.textSecondary.withOpacity(0.7),
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: VoidTheme.surface,
      onTap: () => onTabSelected(id, null),
    );
  }
}
