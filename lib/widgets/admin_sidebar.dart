import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/role_labels.dart';
import 'error_dialog.dart';
import 'about_dialog.dart';

// Every screen mounts its own AdminSidebar and each named route owns its own
// PageStorageBucket (see Flutter's ModalRoute), so a PageStorageKey alone
// can't carry the nav scroll position across screens. This static offset is
// shared app-wide instead, read on mount and updated as the user scrolls.
double _navScrollOffset = 0;

class AdminSidebar extends StatefulWidget {
  final String currentRoute;
  const AdminSidebar({super.key, required this.currentRoute});

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

/// Screens that make sense without a picked organization.
const _orgFreeRoutes = {
  Routes.organizations,
  Routes.systemConfig,
  Routes.systemAudit,
  Routes.profile,
};

class _AdminSidebarState extends State<AdminSidebar> {
  late final ScrollController _navController;

  @override
  void initState() {
    super.initState();
    _navController = ScrollController(initialScrollOffset: _navScrollOffset);
    _navController.addListener(() => _navScrollOffset = _navController.offset);
  }

  @override
  void dispose() {
    _navController.dispose();
    super.dispose();
  }

  /// Reloads role and permissions from the server; a gone session signs out.
  Future<void> _refreshSession(BuildContext context) async {
    final auth = context.read<AuthState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await auth.refreshSession();
      messenger.showSnackBar(const SnackBar(content: Text('Session refreshed.')));
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        auth.logout();
        nav.pushReplacementNamed(Routes.login);
      } else if (context.mounted) {
        showErrorDialog(context, e.message);
      }
    } catch (e) {
      if (context.mounted) showErrorDialog(context, 'Could not refresh the session: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = widget.currentRoute;
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthState>();
    // A super-admin with several organizations and none picked would only see
    // empty data on org-scoped screens: send them to pick one first.
    if (auth.needsOrganizationPick && !_orgFreeRoutes.contains(currentRoute)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.read<AuthState>().needsOrganizationPick) {
          Navigator.of(context).pushReplacementNamed(Routes.organizations);
        }
      });
    }
    final username = auth.username ?? '';
    final roleName = auth.roleName;
    // Accounts (users table) is SUPER_ADMIN-only. Employees/Devices are
    // permission-gated so BRANCH_ADMIN and ORGANIZATION_OWNER both see them.
    final canManageUsers = auth.hasPermission('MANAGE_USERS');
    final canManageEmployees = auth.hasPermission('MANAGE_EMPLOYEES');
    final canManageDevices = auth.hasPermission('MANAGE_DEVICES');
    final canManageStores = auth.hasPermission('MANAGE_STORES');

    return Container(
      width: 220,
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User header — tap through to the "My Profile" screen.
          InkWell(
            onTap: currentRoute == Routes.profile
                ? null
                : () => Navigator.of(context).pushNamed(Routes.profile),
            child: Container(
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                          Tooltip(
                            message: 'Refresh session (reload permissions)',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _refreshSession(context),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(Icons.sync, size: 16, color: scheme.onPrimaryContainer),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(roleDisplayName(roleName),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                                    fontSize: 11)),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              size: 14, color: scheme.onPrimaryContainer.withValues(alpha: 0.7)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          ),

          // Super-admin: pick the organization the whole session acts as.
          if (auth.isSuperAdmin && auth.organizations.isNotEmpty)
            Container(
              width: double.infinity,
              color: scheme.primaryContainer,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: DropdownButtonFormField<int>(
                // Several organizations: starts on the hint; one: preselected.
                initialValue: auth.actingOrganization?.id,
                isExpanded: true,
                hint: const Text('Pick organization'),
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder(), filled: true),
                items: [
                  for (final o in auth.organizations)
                    DropdownMenuItem(value: o.id, child: Text(o.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) {
                  if (id == null || id == auth.actingOrganization?.id) return;
                  context.read<AuthState>().selectOrganization(
                      auth.organizations.firstWhere((o) => o.id == id));
                  // Reload the current screen for the new organization; from the
                  // Organizations screen go on to the dashboard.
                  Navigator.of(context).pushReplacementNamed(
                      currentRoute == Routes.organizations ? Routes.dashboard : currentRoute);
                },
              ),
            ),

          // Nav
          Expanded(
            child: ListView(
              controller: _navController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  route: Routes.dashboard,
                  current: currentRoute,
                ),
                _NavGroup('Reporting', current: currentRoute, children: [
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Orders',
                  route: Routes.orders,
                  current: currentRoute,
                  indent: true,
                ),
                if (auth.apiLevel >= 3 && auth.hasPermission('VIEW_COUPONS'))
                  _NavItem(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Coupon Sales',
                    route: Routes.couponReport,
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
                ]),
                _NavGroup('Inventory', current: currentRoute, children: [
                _NavItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Stock',
                  route: Routes.inventoryStock,
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
                  icon: Icons.badge_outlined,
                  label: 'Visits',
                  route: Routes.inventoryVisits,
                  current: currentRoute,
                  indent: true,
                ),
                ]),
                _NavGroup('Catalog', current: currentRoute, children: [
                _NavItem(
                  icon: Icons.grid_view_outlined,
                  label: 'Products',
                  route: Routes.products,
                  current: currentRoute,
                  indent: true,
                ),
                if (auth.hasPermission('VIEW_PRODUCTS'))
                  _NavItem(
                    icon: Icons.search_off_outlined,
                    label: 'Missing Products',
                    route: Routes.missingProducts,
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
                ]),
                _NavGroup('Marketing', current: currentRoute, children: [
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
                // Offers exist from backend api level 2; older backends have no endpoint.
                if (auth.apiLevel >= 2 && auth.hasPermission('VIEW_OFFERS'))
                  _NavItem(
                    icon: Icons.local_offer_outlined,
                    label: 'Offers',
                    route: Routes.offers,
                    current: currentRoute,
                    indent: true,
                  ),
                if (auth.apiLevel >= 3 && auth.hasPermission('VIEW_COUPONS'))
                  _NavItem(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Coupons',
                    route: Routes.coupons,
                    current: currentRoute,
                    indent: true,
                  ),
                ]),
                _NavGroup('Administration', current: currentRoute, children: [
                if (canManageStores)
                  _NavItem(
                    icon: Icons.tune,
                    label: 'Organization Settings',
                    route: Routes.organizationProperties,
                    current: currentRoute,
                    indent: true,
                  ),
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
                ]),
                if (canManageDevices) _NavGroup('Devices Management', current: currentRoute, children: [
                  _NavItem(
                    icon: Icons.devices_outlined,
                    label: 'Devices',
                    route: Routes.devices,
                    current: currentRoute,
                    indent: true,
                  ),
                  _NavItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Device Logs',
                    route: Routes.deviceLogs,
                    current: currentRoute,
                    indent: true,
                  ),
                  _NavItem(
                    icon: Icons.wifi_tethering_outlined,
                    label: 'Device Status',
                    route: Routes.deviceStatus,
                    current: currentRoute,
                    indent: true,
                  ),
                ]),
                _NavGroup('Integrations', current: currentRoute, children: [
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
                // System settings and audit exist from backend api level 3, super-admin only.
                ]),
                if (auth.apiLevel >= 3 && auth.hasPermission('MANAGE_SYSTEM')) _NavGroup('System', current: currentRoute, children: [
                  // Only worth a screen when there is a choice to make.
                  if (auth.organizations.length > 1)
                    _NavItem(
                      icon: Icons.apartment_outlined,
                      label: 'Organizations',
                      route: Routes.organizations,
                      current: currentRoute,
                      indent: true,
                    ),
                  _NavItem(
                    icon: Icons.settings_applications_outlined,
                    label: 'System Configuration',
                    route: Routes.systemConfig,
                    current: currentRoute,
                    indent: true,
                  ),
                  _NavItem(
                    icon: Icons.history_outlined,
                    label: 'System Audit',
                    route: Routes.systemAudit,
                    current: currentRoute,
                    indent: true,
                  ),
                ]),
              ],
            ),
          ),

          Divider(height: 1, color: scheme.outlineVariant),
          ListTile(
            leading: const Icon(Icons.info_outline, size: 20),
            title: const Text('About', style: TextStyle(fontSize: 14)),
            dense: true,
            onTap: () => showAboutInfoDialog(context),
          ),
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

/// Groups the user has opened, kept app-wide for the same reason as the nav
/// scroll offset: every screen mounts its own sidebar.
final Set<String> _openGroups = {};

/// Collapsible sidebar section. The one holding the current page opens itself
/// when the sidebar mounts; after that only the user opens or closes it.
class _NavGroup extends StatefulWidget {
  final String title;
  final String current;
  final List<Widget> children;
  const _NavGroup(this.title, {required this.current, required this.children});

  @override
  State<_NavGroup> createState() => _NavGroupState();
}

class _NavGroupState extends State<_NavGroup> {
  bool get _holdsCurrent =>
      widget.children.any((c) => c is _NavItem && c.route == widget.current);

  @override
  void initState() {
    super.initState();
    if (_holdsCurrent) _openGroups.add(widget.title);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = _openGroups.contains(widget.title);
    final active = _holdsCurrent;
    final color = active ? scheme.primary : scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: active && !open ? scheme.primaryContainer : Colors.transparent,
          child: InkWell(
            onTap: () => setState(() {
              if (open) {
                _openGroups.remove(widget.title);
              } else {
                _openGroups.add(widget.title);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                            color: color)),
                  ),
                  Icon(open ? Icons.expand_more : Icons.chevron_right,
                      size: 18, color: active ? scheme.primary : scheme.outline),
                ],
              ),
            ),
          ),
        ),
        if (open) ...widget.children,
      ],
    );
  }
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
