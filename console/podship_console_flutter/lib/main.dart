import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import 'client.dart';
import 'l10n/gen/app_localizations.dart';
import 'screens/integrations_screen.dart';
import 'screens/sign_in_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await initializeClient();
  runApp(const ConsoleApp());
}

class ConsoleApp extends StatelessWidget {
  const ConsoleApp({super.key, this.home, this.googleFonts = true});

  /// For tests.
  final Widget? home;
  final bool googleFonts;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, googleFonts: googleFonts),
      darkTheme: buildTheme(Brightness.dark, googleFonts: googleFonts),
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) =>
          locale?.languageCode == 'es'
          ? const Locale('es')
          : const Locale('en'),
      home: home ?? const _Root(),
    );
  }
}

/// Signed in: the integrations page. Else sign-in (with a link token when
/// the URL is `/sign-in/link/<token>`).
class _Root extends StatelessWidget {
  const _Root();

  static String? linkToken() {
    final segs = Uri.base.pathSegments;
    final i = segs.indexOf('link');
    if (i > 0 && segs[i - 1] == 'sign-in' && i + 1 < segs.length) {
      return segs[i + 1];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: client.auth.authInfoListenable,
      builder: (context, _) => client.auth.isAuthenticated
          ? const IntegrationsScreen()
          : SignInScreen(linkToken: linkToken()),
    );
  }
}
