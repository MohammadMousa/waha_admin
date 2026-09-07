/// Humanized labels for backend role names (`SUPER_ADMIN`, `ORGANIZATION_OWNER`, …).
/// Keep the admin app's UI vocabulary in one place instead of re-deriving it per screen.
const Map<String, String> kRoleDisplayNames = {
  'SUPER_ADMIN': 'Super Admin',
  'ORGANIZATION_OWNER': 'Organization Owner',
  'BRANCH_ADMIN': 'Branch Admin',
  'OPERATOR': 'Operator',
  'CASHIER': 'Cashier',
  'KIOSK': 'Kiosk',
};

String roleDisplayName(String? role) {
  if (role == null || role.isEmpty) return 'User';
  return kRoleDisplayNames[role] ?? role;
}
