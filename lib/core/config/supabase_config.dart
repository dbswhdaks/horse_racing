import 'dart:convert';

import 'package:flutter/services.dart';

import '../constants/supabase_constants.dart';

/// Supabase URL/anon key 로드 순서:
/// 1. 빌드 시 `--dart-define=SUPABASE_URL=...` 및 `--dart-define=SUPABASE_ANON_KEY=...`
/// 2. `assets/config/runtime_secrets.json` 의 `supabaseUrl`, `supabaseAnonKey` (빈 값이면 스킵)
/// 3. [SupabaseConstants] (앱에 포함된 기본값)
class SupabaseConfig {
  SupabaseConfig._();

  static Future<({String url, String anonKey})> load() async {
    const envUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    const envKey =
        String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

    var url = envUrl.trim();
    var anonKey = envKey.trim();

    if (url.isEmpty || anonKey.isEmpty) {
      try {
        final raw = await rootBundle.loadString(
          'assets/config/runtime_secrets.json',
        );
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (url.isEmpty) {
            final u = (decoded['supabaseUrl'] ?? '').toString().trim();
            if (u.isNotEmpty) url = u;
          }
          if (anonKey.isEmpty) {
            final a = (decoded['supabaseAnonKey'] ?? '').toString().trim();
            if (a.isNotEmpty) anonKey = a;
          }
        }
      } catch (_) {
        // 누락/파싱 실패 → 아래 기본값
      }
    }

    if (url.isEmpty) url = SupabaseConstants.url;
    if (anonKey.isEmpty) anonKey = SupabaseConstants.anonKey;
    return (url: url, anonKey: anonKey);
  }
}
