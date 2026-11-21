import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'state.dart';
import 'widgets/logo.dart';

const seed = Color(0xFF7C5CFF);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b).copyWith(
    surface: dark ? const Color(0xFF0E1024) : const Color(0xFFF7F6FB),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardTheme(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF171A33) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: dark ? const Color(0xFF252A4A) : const Color(0xFFE6E3F0)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1D2140) : const Color(0xFFF0EEF8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class StrataApp extends StatefulWidget {
  const StrataApp({super.key});

  @override
  State<StrataApp> createState() => _StrataAppState();
}

class _StrataAppState extends State<StrataApp> {
  @override
  void initState() {
    super.initState();
    app.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final theme = app.settings['theme'] as String? ?? 'dark';
        return MaterialApp(
          title: 'Strata VM',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: switch (theme) {
            'light' => ThemeMode.light,
            'system' => ThemeMode.system,
            _ => ThemeMode.dark,
          },
          home: app.ready ? const HomeScreen() : const SetupScreen(),
        );
      },
    );
  }
}

/// İlk açılışta QEMU çalışma ortamı açılırken gösterilen ekran.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StrataLogo(size: 110),
              const SizedBox(height: 28),
              const StrataWordmark(size: 30),
              const SizedBox(height: 40),
              if (app.setupError == null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: app.setupProgress <= 0 ? null : app.setupProgress,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  app.setupProgress <= 0
                      ? t('Hazırlanıyor…', 'Getting ready…')
                      : '${t('Sanal makine motoru kuruluyor', 'Installing the VM engine')}  '
                          '${(app.setupProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ] else ...[
                Text(app.setupError!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                const SizedBox(height: 16),
                FilledButton(onPressed: app.init, child: Text(t('Tekrar dene', 'Retry'))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
