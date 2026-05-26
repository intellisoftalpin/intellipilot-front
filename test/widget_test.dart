import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intellipilot/main.dart';

void main() {
  testWidgets('App boots and shows the welcome screen', (tester) async {
    await tester.pumpWidget(const IntelliPilotApp());
    await tester.pumpAndSettle();

    // The English ARB defines these strings. Using AppLocalizations directly
    // would require a context; this is good enough as a smoke test.
    expect(find.text('IntelliPilot'), findsWidgets);
    expect(find.text('Welcome to IntelliPilot'), findsOneWidget);
  });

  test('AppLocalizations bindings expose at least English', () {
    expect(AppLocalizations.supportedLocales, isNotEmpty);
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode),
      contains('en'),
    );
  });
}
