class Routes {
  static const login           = '/login';
  static const dashboard       = '/dashboard';
  static const productsSales   = '/reports/products-sales';
  static const orders          = '/reports/orders';

  // Administration
  static const stores          = '/stores';
  static const storeEdit       = '/stores/edit';
  static const accounts        = '/accounts';
  static const accountEdit     = '/accounts/edit';
  static const employees       = '/employees';
  static const employeeEdit    = '/employees/edit';
  static const devices         = '/devices';
  static const deviceEdit      = '/devices/edit';
  static const register        = '/register';

  // Catalog
  static const products        = '/products';

  // Marketing
  static const advertisements  = '/advertisements';
  static const landingPages    = '/landing-pages';

  // Reporting
  static const charts          = '/reports/charts';

  // Global admin
  static const paymentMethodsGlobal    = '/payment-methods/global';
  static const receiptInfoGlobal       = '/receipt-info/global';
  static const resourceExplorerGlobal  = '/resources/global';

  // Store-scoped (pushed with Store as argument)
  static const categories      = '/store/categories';
  static const categoryEdit    = '/category/edit';
  static const productEdit     = '/product/edit';
  static const paymentMethods  = '/payment-methods';
  static const receiptInfoEdit = '/receipt-info/edit';
  static const odooAdmin          = '/integrations/odoo';
  static const integrationLogs    = '/integrations/logs';
  static const resourceExplorer = '/resources';
  static const landingEditor   = '/landing-editor';
}
