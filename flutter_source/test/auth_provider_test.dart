import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/providers/auth_provider.dart';

/// Regression test for AuthProvider.hasPermission's empty-string rule
/// (app_router.dart's '/inbox' NavEntry relies on this): calling/messaging
/// staff was never RBAC-gated in the first place, so a NavEntry that just
/// surfaces it declares permission: '' rather than inventing a permission
/// name, and hasPermission must treat that as "always allowed" for every
/// role, not just superadmin.
void main() {
  test('hasPermission treats an empty permission string as always-allowed', () {
    final auth = AuthProvider();
    expect(auth.hasPermission(''), isTrue);
  });

  test('hasPermission still gates a real permission name for a non-superadmin role', () {
    final auth = AuthProvider();
    expect(auth.hasPermission('view_admin'), isFalse);
  });
}
