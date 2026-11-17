import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/role_labels.dart';
import 'error_dialog.dart';
import 'about_dialog.dart';
import 'waha_filter_controls.dart';

// Every screen mounts its own AdminSidebar and each named route owns its own
// PageStorageBucket (see Flutter's ModalRoute), so a PageStorageKey alone
// can't carry the nav scroll position across screens. This static offset is
// shared app-wide instead, read on mount and updated as the user scrolls.
double _navScrollOffset = 0;

// Collapsed (icon-only) sidebar on wide screens. App-wide for the same reason,
// and remembered between launches.
final ValueNotifier<bool> _collapsed = ValueNotifier(false);
bool _collapsedLoaded = false;
const _kExpandedWidth = 240.0;
const _kCollapsedWidth = 72.0;

/// Tells the nav items whether to draw themselves icon-only.
class _SidebarMode extends InheritedWidget {
  final bool compact;
  const _SidebarMode({required this.compact, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SidebarMode>()?.compact ?? false;

  @override
  bool updateShouldNotify(_SidebarMode old) => old.compact != compact;
}

class AdminSidebar extends StatefulWidget {
  final String currentRoute;

  /// True when shown inside the phone slide-out panel (full width).
  final bool inDrawer;
  const AdminSidebar({super.key, required this.currentRoute, this.inDrawer = false});

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
    _collapsed.addListener(_onCollapsedChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAvatar();
    });
    if (!_collapsedLoaded) {
      _collapsedLoaded = true;
      SharedPreferences.getInstance().then((prefs) {
        _collapsed.value = prefs.getBool('admin_sidebar_collapsed') ?? false;
      }).catchError((_) {});
    }
  }

  /// Organization shown as a plain label (no arrow, not clickable) when the
  /// person cannot switch organizations.
  Widget _organizationLabel(BuildContext context, String? name) {
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: kWahaFilterControlHeight,
      padding: kWahaFilterControlPadding,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: kWahaFilterControlRadius,
        color: Color.alphaBlend(scheme.primary.withValues(alpha: 0.05), scheme.surface),
      ),
      child: Row(
        children: [
          Icon(Icons.business_outlined, size: 16, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: kWahaFilterControlFontSize)),
          ),
        ],
      ),
    );
  }

  /// Own picture for the user card (api level 5), fetched once per sign-in.
  Future<void> _loadAvatar() async {
    if (!mounted) return;
    final auth = context.read<AuthState>();
    final token = auth.token;
    if (token == null || auth.apiLevel < 5 || auth.avatarLoaded) return;
    try {
      final p = await ApiClient().getProfile(token);
      if (mounted) auth.setAvatar((p['avatarResourceId'] as num?)?.toInt());
    } catch (_) {
      // The initial letter stays; nothing else depends on it.
    }
  }

  void _onCollapsedChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleCollapsed() async {
    _collapsed.value = !_collapsed.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('admin_sidebar_collapsed', _collapsed.value);
    } catch (_) {}
  }

  void _pickOrganization(AuthState auth, int? id) {
    if (id == null || id == auth.actingOrganization?.id) return;
    context.read<AuthState>().selectOrganization(
        auth.organizations.firstWhere((o) => o.id == id));
    // Reload the current screen for the new organization; from the
    // Organizations screen go on to the dashboard.
    Navigator.of(context).pushReplacementNamed(
        widget.currentRoute == Routes.organizations ? Routes.dashboard : widget.currentRoute);
  }

  @override
  void dispose() {
    _collapsed.removeListener(_onCollapsedChanged);
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
    final canManageRoles = auth.hasPermission('MANAGE_ROLES');
    final canManageDevices = auth.hasPermission('MANAGE_DEVICES');

    // On phones the screens do not get a pinned sidebar; the shell shows this
    // same content in a slide-out panel instead.
    if (!widget.inDrawer && MediaQuery.sizeOf(context).width < 700) {
      return const SizedBox.shrink();
    }

    final collapsedWanted = !widget.inDrawer && _collapsed.value;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      clipBehavior: Clip.hardEdge,
      width: widget.inDrawer
          ? double.infinity
          : (collapsedWanted ? _kCollapsedWidth : _kExpandedWidth),
      color: widget.inDrawer ? scheme.surfaceContainerHigh : scheme.surface,
      // The icon-only layout takes over once the width is small enough, so
      // nothing overflows while the width animates.
      child: LayoutBuilder(builder: (context, box) {
        final compact = !widget.inDrawer && box.maxWidth < 150;
        return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar: collapse button and, for a super-admin, the organization
          // the whole session acts as.
          if (compact)
            Container(
              width: double.infinity,
              color: scheme.primaryContainer,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  IconButton(
                    tooltip: 'Expand menu',
                    icon: Icon(Icons.menu, color: scheme.onPrimaryContainer),
                    onPressed: _toggleCollapsed,
                  ),
                  if (!(auth.isSuperAdmin && auth.organizations.isNotEmpty))
                    Tooltip(
                      message: auth.appName,
                      child: SizedBox(
                        height: 48,
                        child: Icon(Icons.business_outlined, color: scheme.onPrimaryContainer),
                      ),
                    ),
                  if (auth.isSuperAdmin && auth.organizations.isNotEmpty)
                    PopupMenuButton<int>(
                      tooltip: auth.actingOrganization?.name ?? 'Pick organization',
                      icon: Icon(Icons.business, color: scheme.onPrimaryContainer),
                      onSelected: (id) => _pickOrganization(auth, id),
                      itemBuilder: (_) => [
                        for (final o in auth.organizations)
                          CheckedPopupMenuItem<int>(
                            value: o.id,
                            checked: o.id == auth.actingOrganization?.id,
                            child: Text(o.name),
                          ),
                      ],
                    ),
                ],
              ),
            )
          else if (!widget.inDrawer || (auth.isSuperAdmin && auth.organizations.isNotEmpty))
            Container(
              width: double.infinity,
              color: scheme.primaryContainer,
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: auth.isSuperAdmin && auth.organizations.isNotEmpty
                        ? WahaFilterDropdown<int?>(
                            value: auth.actingOrganization?.id,
                            hint: 'Pick organization',
                            expand: true,
                            fillColor: Color.alphaBlend(
                                scheme.primary.withValues(alpha: 0.05), scheme.surface),
                            items: [
                              for (final o in auth.organizations)
                                DropdownMenuItem<int?>(value: o.id, child: Text(o.name)),
                            ],
                            onChanged: (id) => _pickOrganization(auth, id),
                          )
                        : _organizationLabel(
                            context, auth.appName),
                  ),
                  if (!widget.inDrawer)
                    IconButton(
                      tooltip: 'Collapse menu',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.menu_open, color: scheme.onPrimaryContainer),
                      onPressed: _toggleCollapsed,
                    ),
                ],
              ),
            ),

          // Nav
          Expanded(
            child: _SidebarMode(
              compact: compact,
              child: ListView(
              controller: _navController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (auth.canViewReports)
                  _NavItem(
                    icon: Icons.dashboard_outlined,
                    label: 'Dashboard',
                    route: Routes.dashboard,
                    current: currentRoute,
                    topLevel: true,
                  ),
                _NavGroup('Reporting', Icons.bar_chart_outlined, current: currentRoute, children: [
                if (auth.hasPermission('VIEW_ALL_ORDERS')) _NavItem(
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
                if (auth.canViewReports) ...[
                  _NavItem(
                    icon: Icons.shopping_bag_outlined,
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
                ],
                ]),
                _NavGroup('Inventory', Icons.warehouse_outlined, current: currentRoute, children: [
                if (auth.canViewInventoryReports) _NavItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Stock',
                  route: Routes.inventoryStock,
                  current: currentRoute,
                  indent: true,
                ),
                if (auth.canViewInventoryReports) _NavItem(
                  icon: Icons.north_east_outlined,
                  label: 'Transfers',
                  route: Routes.inventoryTransfers,
                  current: currentRoute,
                  indent: true,
                ),
                if (auth.canViewInventoryReports) _NavItem(
                  icon: Icons.south_west_outlined,
                  label: 'Returns',
                  route: Routes.inventoryReturns,
                  current: currentRoute,
                  indent: true,
                ),
                if (auth.canViewInventoryReports) _NavItem(
                  icon: Icons.badge_outlined,
                  label: 'Visits',
                  route: Routes.inventoryVisits,
                  current: currentRoute,
                  indent: true,
                ),
                if (auth.canViewWastes) _NavItem(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Wastes',
                  route: Routes.inventoryWastes,
                  current: currentRoute,
                  indent: true,
                ),
                ]),
                _NavGroup('Catalog', Icons.category_outlined, current: currentRoute, children: [
                if (auth.hasPermission('VIEW_PRODUCTS')) _NavItem(
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
                _NavGroup('Marketing', Icons.campaign_outlined, current: currentRoute, children: [
                if (auth.hasPermission('EDIT_RESOURCES')) _NavItem(
                  icon: Icons.burst_mode_outlined,
                  label: 'Advertisements',
                  route: Routes.advertisements,
                  current: currentRoute,
                  indent: true,
                ),
                if (auth.hasPermission('EDIT_RESOURCES')) _NavItem(
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
                _NavGroup('Administration', Icons.admin_panel_settings_outlined, current: currentRoute, children: [
                if (auth.canManageSettings)
                  _NavItem(
                    icon: Icons.tune,
                    label: 'Organization Settings',
                    route: Routes.organizationProperties,
                    current: currentRoute,
                    indent: true,
                  ),
                if (auth.hasPermission('MANAGE_STORES')) _NavItem(
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
                if (canManageRoles)
                  _NavItem(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Roles',
                    route: Routes.roles,
                    current: currentRoute,
                    indent: true,
                  ),
                if (auth.canManagePaymentMethods)
                  _NavItem(
                    icon: Icons.payment_outlined,
                    label: 'Payment Methods',
                    route: Routes.paymentMethodsGlobal,
                    current: currentRoute,
                    indent: true,
                  ),
                if (auth.canManageSettings)
                  _NavItem(
                    icon: Icons.receipt_outlined,
                    label: 'Receipt Info',
                    route: Routes.receiptInfoGlobal,
                    current: currentRoute,
                    indent: true,
                  ),
                if (auth.hasPermission('EDIT_RESOURCES')) _NavItem(
                  icon: Icons.folder_outlined,
                  label: 'Files Manager',
                  route: Routes.resourceExplorerGlobal,
                  current: currentRoute,
                  indent: true,
                ),
                ]),
                if (canManageDevices) _NavGroup('Devices Management', Icons.devices_other_outlined, current: currentRoute, children: [
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
                if (auth.canManageIntegrations) _NavGroup('Integrations', Icons.extension_outlined, current: currentRoute, children: [
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
                if (auth.apiLevel >= 3 && auth.hasPermission('MANAGE_SYSTEM')) _NavGroup('System', Icons.settings_outlined, current: currentRoute, children: [
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
                ]),
                if (auth.canViewAudit) _NavGroup('Audit', Icons.history_outlined, current: currentRoute, children: [
                  _NavItem(
                    icon: Icons.history_outlined,
                    label: 'Audit',
                    route: Routes.systemAudit,
                    current: currentRoute,
                    indent: true,
                  ),
                ]),
              ],
            ),
            ),
          ),

          Divider(height: 1, color: scheme.outlineVariant),
          _userMenu(context, compact, username, roleName, currentRoute),
        ],
        );
      }),
    );
  }

  /// Signed-in user at the bottom; tapping opens profile, about, refresh and sign out.
  Widget _userMenu(
      BuildContext context, bool compact, String username, String? roleName, String currentRoute) {
    final scheme = Theme.of(context).colorScheme;
    final initial = username.isEmpty ? '' : username.characters.first.toUpperCase();
    final avatarId = context.watch<AuthState>().avatarResourceId;
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: scheme.primaryContainer,
      foregroundImage:
          avatarId == null ? null : NetworkImage(ApiClient().resourceUrl(avatarId)),
      onForegroundImageError: avatarId == null ? null : (_, __) {},
      child: initial.isEmpty
          ? Icon(Icons.person_outline, size: 18, color: scheme.primary)
          : Text(initial,
              style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
    );
    return PopupMenuButton<String>(
      tooltip: compact ? '$username · ${roleDisplayName(roleName)}' : '',
      // Opens above the card (beside it when collapsed) so the pointer never
      // lands on an item, Sign out in particular.
      position: PopupMenuPosition.over,
      offset: Offset(compact ? _kCollapsedWidth : 8, -250),
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      onSelected: (v) {
        switch (v) {
          case 'profile':
            if (currentRoute != Routes.profile) {
              Navigator.of(context).pushNamed(Routes.profile);
            }
          case 'about':
            showAboutInfoDialog(context);
          case 'refresh':
            _refreshSession(context);
          case 'signout':
            context.read<AuthState>().logout();
            Navigator.of(context).pushReplacementNamed(Routes.login);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: 'profile',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_outline, size: 20),
                title: Text('Profile'))),
        const PopupMenuItem(
            value: 'about',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline, size: 20),
                title: Text('About'))),
        const PopupMenuItem(
            value: 'refresh',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.sync, size: 20),
                title: Text('Refresh permissions'))),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: 'signout',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout_outlined, size: 20, color: scheme.error),
                title: Text('Sign out', style: TextStyle(color: scheme.error)))),
      ],
      child: compact
          ? SizedBox(height: 56, width: double.infinity, child: Center(child: avatar))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(username,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(roleDisplayName(roleName),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.unfold_more, size: 18, color: scheme.outline),
                ],
              ),
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
  final IconData icon;
  final String current;
  final List<Widget> children;
  const _NavGroup(this.title, this.icon, {required this.current, required this.children});

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
    // A group whose items are all hidden by permissions is not shown at all.
    if (widget.children.isEmpty) return const SizedBox.shrink();
    // A group left with a single item is just a link: no extra nesting.
    if (widget.children.length == 1 && widget.children.first is _NavItem) {
      final only = widget.children.first as _NavItem;
      return _NavItem(
        icon: only.icon,
        label: only.label,
        route: only.route,
        current: only.current,
        topLevel: true,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final open = _openGroups.contains(widget.title);
    final active = _holdsCurrent;
    final color = active ? scheme.primary : scheme.onSurface;
    if (_SidebarMode.of(context)) {
      // Icon only; the items open in a floating menu beside the sidebar.
      final items = widget.children.whereType<_NavItem>().toList();
      return Material(
        color: active ? scheme.primaryContainer : Colors.transparent,
        child: PopupMenuButton<String>(
          tooltip: widget.title,
          position: PopupMenuPosition.over,
          offset: const Offset(_kCollapsedWidth, 0),
          onSelected: (route) {
            if (route != widget.current) {
              Navigator.of(context).pushReplacementNamed(route);
            }
          },
          itemBuilder: (_) => [
            for (final i in items)
              PopupMenuItem<String>(
                value: i.route,
                child: Row(children: [
                  Icon(i.icon,
                      size: 18,
                      color: i.route == widget.current ? scheme.primary : scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(i.label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: i.route == widget.current ? FontWeight.w600 : FontWeight.normal)),
                ]),
              ),
          ],
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: Icon(widget.icon, size: 22, color: active ? scheme.primary : scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          // Group titles are tinted so they stand out from the items below.
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
                  Icon(widget.icon, size: 20, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
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

  /// Top-level link (not inside a group): drawn like a group header.
  final bool topLevel;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.current,
    this.indent = false,
    this.topLevel = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = current == route;
    if (_SidebarMode.of(context)) {
      return Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: () {
              if (!selected) {
                Navigator.of(context).pushReplacementNamed(route);
              }
            },
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: Icon(icon,
                  size: 22, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      child: ListTile(
        selected: selected,
        contentPadding: EdgeInsets.only(left: indent ? 28 : 16, right: 16),
        leading: Icon(icon,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 20),
        minLeadingWidth: topLevel ? 20 : null,
        horizontalTitleGap: topLevel ? 12 : null,
        title: Text(label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: topLevel ? 14 : 13,
                fontWeight: topLevel
                    ? FontWeight.w700
                    : (selected ? FontWeight.w600 : FontWeight.normal),
                color: selected ? scheme.primary : scheme.onSurface)),
        dense: true,
        onTap: () {
          if (!selected) Navigator.of(context).pushReplacementNamed(route);
        },
      ),
    );
  }
}
