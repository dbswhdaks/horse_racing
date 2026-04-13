import 'dart:convert';

import 'package:flutter/services.dart';

class RuntimeSecretsService {
  RuntimeSecretsService._();

  static String? _cachedYoutubeApiKey;

  static Future<String> getYoutubeApiKey() async {
    if (_cachedYoutubeApiKey != null) return _cachedYoutubeApiKey!;

    const fromDefine = String.fromEnvironment(
      'YOUTUBE_API_KEY',
      defaultValue: '',
    );
    if (fromDefine.isNotEmpty) {
      _cachedYoutubeApiKey = fromDefine.trim();
      return _cachedYoutubeApiKey!;
    }

    try {
      final raw = await rootBundle.loadString(
        'assets/config/runtime_secrets.json',
      );
      final jsonMap = jsonDecode(raw);
      if (jsonMap is Map<String, dynamic>) {
        final key = (jsonMap['youtubeApiKey'] ?? '').toString().trim();
        _cachedYoutubeApiKey = key;
        return key;
      }
    } catch (_) {
      // 파일이 없거나 파싱 실패 시 빈 키 반환 (fallback 로직 사용)
    }

    _cachedYoutubeApiKey = '';
    return _cachedYoutubeApiKey!;
  }
}
