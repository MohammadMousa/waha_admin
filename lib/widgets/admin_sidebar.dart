import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../router/routes.dart';
import '../state/auth_state.dart';
import '../utils/role_labels.dart';

class AdminSidebar extends StatelessWidget {
  final String currentRoute;
  const AdminSidebar({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthState>();
    final username = auth.username ?? '';
    final roleName = auth.roleName;
    // Accounts (users table) is SUPER_ADMIN-only. Employees/Devices are
    // permission-gated so BRANCH_ADMIN and ORGANIZATION_OWNER both see them.
    final canManageUsers = auth.hasPermission('MANAGE_USERS');
    final canManageEmployees = auth.hasPermission('MANAGE_EMPLOYEES');
    final canManageDevices = auth.hasPermission('MANAGE_DEVICES');

    return Container(
      width: 220,
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            color: scheme.primaryContainer,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.person_outline, color: scheme.onPrimary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Text(roleDisplayName(roleName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                              fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Nav
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  route: Routes.dashboard,
                  current: currentRoute,
                ),
                _SectionLabel('Reporting'),
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Orders',
                  route: Routes.orders,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.bar_chart_outlined,
                  label: 'Products Sales',
                  route: Routes.productsSales,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.insert_chart_outlined,
                  label: 'Charts',
                  route: Routes.charts,
                  current: currentRoute,
                  indent: true,
                ),
                _SectionLabel('Inventory'),
                _NavItem(
                  icon: Icons.badge_outlined,
                  label: 'Visits',
                  route: Routes.inventoryVisits,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.north_east_outlined,
                  label: 'Transfers',
                  route: Routes.inventoryTransfers,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.south_west_outlined,
                  label: 'Returns',
                  route: Routes.inventoryReturns,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Stock',
                  route: Routes.inventoryStock,
                  current: currentRoute,
                  indent: true,
                ),
                _SectionLabel('Administration'),
                _NavItem(
                  icon: Icons.store_outlined,
                  label: 'Stores',
                  route: Routes.stores,
                  current: currentRoute,
                  indent: true,
                ),
                if (canManageUsers)
                  _NavItem(
                    icon: Icons.people_outline,
                    label: 'Accounts',
                    route: Routes.accounts,
                    current: currentRoute,
                    indent: true,
                  ),
                if (canManageEmployees)
                  _NavItem(
                    icon: Icons.badge_outlined,
                    label: 'Employees',
                    route: Routes.employees,
                    current: currentRoute,
                    indent: true,
                  ),
                if (canManageDevices)
                  _NavItem(
                    icon: Icons.devices_outlined,
                    label: 'Devices',
                    route: Routes.devices,
                    current: currentRoute,
                    indent: true,
                  ),
                _NavItem(
                  icon: Icons.payment_outlined,
                  label: 'Payment Methods',
                  route: Routes.paymentMethodsGlobal,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.receipt_outlined,
                  label: 'Receipt Info',
                  route: Routes.receiptInfoGlobal,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.folder_outlined,
                  label: 'Files Manager',
                  route: Routes.resourceExplorerGlobal,
                  current: currentRoute,
                  indent: true,
                ),
                _SectionLabel('Marketing'),
                _NavItem(
                  icon: Icons.burst_mode_outlined,
                  label: 'Advertisements',
                  route: Routes.advertisements,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.web_outlined,
                  label: 'Pages',
                  route: Routes.landingPages,
                  current: currentRoute,
                  indent: true,
                ),
                _SectionLabel('Catalog'),
                _NavItem(
                  icon: Icons.grid_view_outlined,
                  label: 'Products',
                  route: Routes.products,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.category_outlined,
                  label: 'Categories',
                  route: Routes.categories,
                  current: currentRoute,
                  indent: true,
                ),
                _SectionLabel('Integrations'),
                _NavItem(
                  icon: Icons.hub_outlined,
                  label: 'Odoo',
                  route: Routes.odooAdmin,
                  current: currentRoute,
                  indent: true,
                ),
                _NavItem(
                  icon: Icons.sync_outlined,
                  label: 'Sync Logs',
                  route: Routes.integrationLogs,
                  current: currentRoute,
                  indent: true,
                ),
              ],
            ),
          ),

          Divider(height: 1, color: scheme.outlineVariant),
          ListTile(
            leading: const Icon(Icons.logout_outlined, size: 20),
            title: const Text('Sign Out', style: TextStyle(fontSize: 14)),
            dense: true,
            onTap: () {
              context.read<AuthState>().logout();
              Navigator.of(context).pushReplacementNamed(Routes.login);
            },
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.outline)),
      );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final String current;
  final bool indent;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.current,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = current == route;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      child: ListTile(
        selected: selected,
        contentPadding: EdgeInsets.only(left: indent ? 28 : 16, right: 16),
        leading: Icon(icon,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 20),
        title: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? scheme.primary : scheme.onSurface)),
        dense: true,
        onTap: () {
          if (!selected) Navigator.of(context).pushReplacementNamed(route);
        },
      ),
    );
  }
}
