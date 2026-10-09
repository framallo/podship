import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podship_console_flutter/main.dart';
import 'package:podship_console_flutter/screens/sign_in_screen.dart';

void main() {
  Future<void> pump(WidgetTester t, Locale locale) async {
    t.platformDispatcher.localesTestValue = [locale];
    addTearDown(t.platformDispatcher.clearLocalesTestValue);
    await t.pumpWidget(
      const ConsoleApp(home: SignInScreen(), googleFonts: false),
    );
    await t.pump();
  }

  testWidgets('sign-in shows the email step in English', (t) async {
    await pump(t, const Locale('en'));
    expect(find.text('Sign in to podship console'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('sign-in shows the email step in Spanish', (t) async {
    await pump(t, const Locale('es'));
    expect(find.text('Entra a podship console'), findsOneWidget);
    expect(find.text('Enviar código'), findsOneWidget);
  });
}
