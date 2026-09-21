// Basic smoke test: the app should build without throwing.
//
// This was previously the default Flutter counter-app template test (it
// asserted a "0"/"1" counter that has never existed in this app). Replaced
// with a real smoke test now that MyApp requires a constructed router.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/app_router.dart';
import 'package:frontend/call/call_service.dart';
import 'package:frontend/main.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/site_config_provider.dart';
import 'package:frontend/providers/theme_provider.dart';

void main() {
  testWidgets('App builds and shows the login screen', (tester) async {
    final authProvider = AuthProvider();
    final router = buildAppRouter(authProvider);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => SiteConfigProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          // MyApp's builder reads CallService unconditionally (for
          // IncomingCallOverlay) regardless of auth state - omitting it
          // throws ProviderNotFoundException before the app ever renders.
          ChangeNotifierProvider(create: (_) => CallService()),
        ],
        child: MyApp(router: router),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
