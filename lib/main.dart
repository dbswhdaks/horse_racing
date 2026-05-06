import 'dart:async';

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
import 'router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 15(API 35)에서 Window.setStatusBarColor / setNavigationBarColor 등이 deprecated 되었기 때문에
  // 색상은 MainActivity.enableEdgeToEdge() 로만 처리하고, 여기서는 아이콘 밝기와 contrast 강제만 지정한다.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  await initializeDateFormatting('ko');

  final supa = await SupabaseConfig.load();
  await Supabase.initialize(
    url: supa.url,
    anonKey: supa.anonKey,
  );

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
