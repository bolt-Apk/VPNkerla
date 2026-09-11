import 'package:fl_clash/kerla/home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('existing-key entry remains available before account API setup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const TestApp(
        wrapInProviderScope: true,
        locale: Locale('ru'),
        child: KerlaHome(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('У меня уже есть ключ'), findsOneWidget);
    expect(find.text('Добавить ключ'), findsOneWidget);
    expect(
      find.text(
        'Регистрация пока недоступна. Можно подключиться по уже выданному ключу.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Добавить ключ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
