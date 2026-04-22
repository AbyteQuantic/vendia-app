import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/splash/animated_splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Seed dotenv so downstream services (ApiConfig.baseUrl, SyncService)
    // don't throw NotInitializedError during the smoke test. Real main()
    // loads from a .env file; tests ship a minimal inline payload.
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('AnimatedSplashScreen renders the VendIA brand',
      (tester) async {
    // VendIAApp boot path spins up Isar + platform channels that aren't
    // available in the widget test binding. The splash screen is the
    // smallest entry widget that still exercises our theme + branding,
    // so the smoke test targets it directly.
    await tester.pumpWidget(const MaterialApp(home: AnimatedSplashScreen()));
    await tester.pump();

    expect(find.text('VendIA'), findsOneWidget);
  });
}
