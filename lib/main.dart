import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/account_user.dart';
import 'models/category.dart';
import 'models/device.dart';
import 'models/employee.dart';
import 'models/store.dart';
import 'router/routes.dart';
import 'screens/account_edit_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/advertisements_screen.dart';
import 'screens/device_edit_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/employee_edit_screen.dart';
import 'screens/employees_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/categories_admin_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/category_edit_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/landing_editor_screen.dart';
import 'screens/landing_pages_screen.dart';
import 'screens/login_screen.dart';
import 'screens/integration_logs_screen.dart';
import 'screens/inventory_operations_screen.dart';
import 'screens/inventory_stock_screen.dart';
import 'screens/inventory_visits_screen.dart';
import 'screens/odoo_admin_screen.dart';
import 'screens/profile_screen.dart';
import 'services/api_client.dart';
import 'screens/payment_methods_screen.dart';
import 'screens/product_edit_screen.dart';
import 'screens/products_sales_screen.dart';
import 'screens/products_screen.dart';
import 'screens/receipt_info_edit_screen.dart';
import 'screens/register_screen.dart';
import 'screens/resource_explorer_screen.dart';
import 'screens/charts_screen.dart';
import 'screens/store_edit_screen.dart';
import 'screens/stores_screen.dart';
import 'state/auth_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthState(),
      child: const WahaAdminApp(),
    ),
  );
}

class WahaAdminApp extends StatelessWidget {
  const WahaAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waha Admin',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case Routes.login:
            return MaterialPageRoute(
                builder: (_) => const LoginScreen(), settings: settings);

          case Routes.dashboard:
            return MaterialPageRoute(
                builder: (_) => const DashboardScreen(), settings: settings);

          case Routes.profile:
            return MaterialPageRoute(
                builder: (_) => const ProfileScreen(), settings: settings);

          case Routes.productsSales:
            return MaterialPageRoute(
                builder: (_) => const ProductsSalesScreen(), settings: settings);

          case Routes.stores:
            return MaterialPageRoute(
                builder: (_) => const StoresScreen(), settings: settings);

          case Routes.storeEdit:
            final store = settings.arguments as Store?;
            return MaterialPageRoute(
                builder: (_) => StoreEditScreen(store: store), settings: settings);

          case Routes.accounts:
            return MaterialPageRoute(
                builder: (_) => const AccountsScreen(), settings: settings);

          case Routes.accountEdit:
            final account = settings.arguments as AccountUser?;
            return MaterialPageRoute(
                builder: (_) => AccountEditScreen(account: account), settings: settings);

          case Routes.employees:
            return MaterialPageRoute(
                builder: (_) => const EmployeesScreen(), settings: settings);

          case Routes.employeeEdit:
            final employee = settings.arguments as Employee?;
            return MaterialPageRoute(
                builder: (_) => EmployeeEditScreen(employee: employee), settings: settings);

          case Routes.devices:
            return MaterialPageRoute(
                builder: (_) => const DevicesScreen(), settings: settings);

          case Routes.deviceEdit:
            final device = settings.arguments as Device?;
            return MaterialPageRoute(
                builder: (_) => DeviceEditScreen(device: device), settings: settings);

          case Routes.register:
            return MaterialPageRoute(
                builder: (_) => const RegisterScreen(), settings: settings);

          case Routes.orders:
            return MaterialPageRoute(
                builder: (_) => const OrdersScreen(), settings: settings);

          case Routes.inventoryVisits:
            return MaterialPageRoute(
                builder: (_) => const InventoryVisitsScreen(), settings: settings);

          case Routes.inventoryTransfers:
            return MaterialPageRoute(
                builder: (_) => InventoryOperationsScreen(
                      title: 'Inventory Transfers',
                      route: Routes.inventoryTransfers,
                      exportFilePrefix: 'inventory_transfers',
                      fetcher: ApiClient().getInventoryTransfers,
                    ),
                settings: settings);

          case Routes.inventoryReturns:
            return MaterialPageRoute(
                builder: (_) => InventoryOperationsScreen(
                      title: 'Inventory Returns',
                      route: Routes.inventoryReturns,
                      exportFilePrefix: 'inventory_returns',
                      fetcher: ApiClient().getInventoryReturns,
                    ),
                settings: settings);

          case Routes.inventoryStock:
            return MaterialPageRoute(
                builder: (_) => const InventoryStockScreen(), settings: settings);

          case Routes.advertisements:
            return MaterialPageRoute(
                builder: (_) => const AdvertisementsScreen(), settings: settings);

          case Routes.landingPages:
            return MaterialPageRoute(
                builder: (_) => const LandingPagesScreen(), settings: settings);

          case Routes.products:
            return MaterialPageRoute(
                builder: (_) => const ProductsScreen(), settings: settings);

          case Routes.categories:
            // With a Store argument → store-scoped view (from Stores screen)
            // Without argument → global picker view (from sidebar)
            return MaterialPageRoute(
                builder: (_) => settings.arguments is Store
                    ? CategoriesScreen(store: settings.arguments as Store)
                    : const CategoriesAdminScreen(),
                settings: settings);

          case Routes.categoryEdit:
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
                builder: (_) => CategoryEditScreen(
                  category: args['category'] as Category,
                  storeSlug: (args['store'] as Store?)?.name ?? args['storeSlug'] as String,
                ),
                settings: settings);

          case Routes.productEdit:
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
                builder: (_) => ProductEditScreen(
                  productId: args['productId'] as int?,
                  storeSlug: args['storeSlug'] as String,
                ),
                settings: settings);

          case Routes.paymentMethods:
            return MaterialPageRoute(
                builder: (_) => PaymentMethodsScreen(
                    store: settings.arguments as Store),
                settings: settings);

          case Routes.receiptInfoEdit:
            return MaterialPageRoute(
                builder: (_) => ReceiptInfoEditScreen(
                    store: settings.arguments as Store),
                settings: settings);

          case Routes.odooAdmin:
            return MaterialPageRoute(
                builder: (_) => const OdooAdminScreen(),
                settings: settings);

          case Routes.integrationLogs:
            return MaterialPageRoute(
                builder: (_) => const IntegrationLogsScreen(),
                settings: settings);

          case Routes.resourceExplorerGlobal:
            return MaterialPageRoute(
                builder: (_) => const ResourceExplorerScreen(),
                settings: settings);

          case Routes.resourceExplorer:
            return MaterialPageRoute(
                builder: (_) => ResourceExplorerScreen(
                    store: settings.arguments as Store),
                settings: settings);

          case Routes.landingEditor:
            final editorArgs = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
                builder: (_) => LandingEditorScreen(
                    store: editorArgs['store'] as Store?,
                    orgSlug: editorArgs['orgSlug'] as String,
                    pageKey: editorArgs['pageKey'] as String? ?? 'KIOSK_LANDING'),
                settings: settings);

          case Routes.charts:
            return MaterialPageRoute(
                builder: (_) => const ChartsScreen(), settings: settings);

          case Routes.paymentMethodsGlobal:
            return MaterialPageRoute(
                builder: (_) => PaymentMethodsScreen(
                    store: const Store(id: 1, name: 'waha')),
                settings: settings);

          case Routes.receiptInfoGlobal:
            return MaterialPageRoute(
                builder: (_) => ReceiptInfoEditScreen(
                    store: const Store(id: 1, name: 'waha')),
                settings: settings);

          default:
            return MaterialPageRoute(
                builder: (_) => const LoginScreen(), settings: settings);
        }
      },
      home: const _Initializer(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5C6BC0),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F6FA),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      fontFamily: 'Inter',
      // Inter has no Arabic glyphs at all — without an explicit fallback,
      // Arabic text (product/category names, etc.) renders as empty tofu
      // boxes instead of silently falling back to the browser default the
      // way Latin text does. Loaded alongside Inter in web/index.html.
      fontFamilyFallback: const ['Noto Sans Arabic'],
    );
  }
}

class _Initializer extends StatefulWidget {
  const _Initializer();

  @override
  State<_Initializer> createState() => _InitializerState();
}

class _InitializerState extends State<_Initializer> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final auth = context.read<AuthState>();
    await auth.init();
    if (!mounted) return;
    setState(() => _ready = true);
    if (auth.isLoggedIn) {
      Navigator.of(context).pushReplacementNamed(Routes.dashboard);
    } else {
      Navigator.of(context).pushReplacementNamed(Routes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const SizedBox.shrink();
  }
}
