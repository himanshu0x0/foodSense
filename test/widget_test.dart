import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foodsense/app/app.dart';
import 'package:foodsense/firebase_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  });

  testWidgets('FoodSense app loads the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FoodSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(
      find.text('New to FoodSense? Create an account'),
      findsOneWidget,
    );
  });
}
