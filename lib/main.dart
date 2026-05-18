import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/config/supabase_connection_check.dart';
import 'core/theme/app_theme.dart';
import 'features/purchase/providers/in_app_purchase_provider.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';

/// 초기화 단계 중 실패해도 앱 자체는 항상 실행되도록 처리한다.
/// (특히 웹에서 빈 화면이 되는 것을 방지)
Future<void> _safeRun(String label, Future<void> Function() task) async {
  try {
    await task();
  } catch (e, st) {
    debugPrint('[init] $label 실패: $e\n$st');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 모바일에서는 시스템 UI 색상 처리, 웹에서는 무시됨.
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  await _safeRun('initializeDateFormatting', () async {
    await initializeDateFormatting('ko');
  });

  await _safeRun('Firebase.initializeApp', () async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  });

  await _safeRun('Supabase.initialize', () async {
    final supa = await SupabaseConfig.load();
    await Supabase.initialize(url: supa.url, anonKey: supa.anonKey);
  });

  if (kDebugMode) {
    unawaited(SupabaseConnectionCheck.logProbe());
  }

  runApp(const ProviderScope(child: HorseRacingApp()));
}

class HorseRacingApp extends ConsumerWidget {
  const HorseRacingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(inAppPurchaseProvider);

    return MaterialApp.router(
      title: '경마 Plus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko'), Locale('en')],
    );
  }
}
