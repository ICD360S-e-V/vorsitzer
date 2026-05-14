import 'package:flutter/material.dart';

/// Sidebar menu item for admin dashboard
class SidebarMenuItem extends StatelessWidget {
  final int index;
  final int selectedIndex;
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool collapsed;

  const SidebarMenuItem({
    super.key,
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.title,
    required this.onTap,
    this.collapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: collapsed ? title : '',
        waitDuration: const Duration(milliseconds: 300),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isSelected ? const Color(0xFF4a90d9) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: collapsed
                ? Center(child: Icon(icon, color: isSelected ? const Color(0xFF4a90d9) : Colors.white70, size: 22))
                : Row(
                    children: [
                      Icon(icon, color: isSelected ? const Color(0xFF4a90d9) : Colors.white70, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Complete sidebar widget for admin dashboard with collapse/expand
class DashboardSidebar extends StatefulWidget {
  final String userName;
  final String mitgliedernummer;
  final int selectedMenuIndex;
  final Function(int) onMenuSelected;

  const DashboardSidebar({
    super.key,
    required this.userName,
    required this.mitgliedernummer,
    required this.selectedMenuIndex,
    required this.onMenuSelected,
  });

  @override
  State<DashboardSidebar> createState() => _DashboardSidebarState();
}

class _DashboardSidebarState extends State<DashboardSidebar> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _collapsed ? 60 : 250,
      color: const Color(0xFF1a1a2e),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Collapse/Expand button
          Align(
            alignment: _collapsed ? Alignment.center : Alignment.centerRight,
            child: IconButton(
              icon: Icon(_collapsed ? Icons.menu_open : Icons.menu, color: Colors.white70, size: 20),
              tooltip: _collapsed ? 'Menü erweitern' : 'Menü einklappen',
              onPressed: () => setState(() => _collapsed = !_collapsed),
            ),
          ),
          // User info (hide when collapsed)
          if (!_collapsed) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFF4a90d9),
                    child: Icon(Icons.person, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                        Text(widget.mitgliedernummer, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF4a90d9),
                child: Text(widget.userName.isNotEmpty ? widget.userName[0] : '?', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 4),
          // Menu items (scrollable)
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _item(0, Icons.dashboard, 'Dashboard'),
                  _item(1, Icons.people, 'Mitgliederverwaltung'),
                  _item(2, Icons.confirmation_number, 'Ticketverwaltung'),
                  _item(3, Icons.calendar_month, 'Terminverwaltung'),
                  _item(4, Icons.business, 'Vereinverwaltung'),
                  _item(5, Icons.location_city, 'Netzwerk'),
                  _item(6, Icons.account_balance_wallet, 'Finanzverwaltung'),
                  _item(7, Icons.bar_chart, 'Statistik'),
                  _item(8, Icons.archive, 'Archiv'),
                  _item(9, Icons.miscellaneous_services, 'Dienste'),
                  _item(10, Icons.repeat, 'Routinenaufgaben'),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          _item(11, Icons.settings, 'Einstellungen'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _item(int index, IconData icon, String title) {
    return SidebarMenuItem(
      index: index,
      selectedIndex: widget.selectedMenuIndex,
      icon: icon,
      title: title,
      onTap: () => widget.onMenuSelected(index),
      collapsed: _collapsed,
    );
  }
}
