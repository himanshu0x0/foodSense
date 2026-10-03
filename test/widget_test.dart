import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foodsense/app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();

    // The Firebase Core test mock provides a default Firebase app.
    // Do not pass DefaultFirebaseOptions.currentPlatform here.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  });

  testWidgets('FoodSense app loads the login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FoodSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('New to FoodSense? Create an account'), findsOneWidget);
  });
}
