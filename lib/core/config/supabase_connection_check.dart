import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 디버그 전용: PostgREST에 `races` 1건만 읽어 연결 여부를 [debugPrint]로 남깁니다.
class SupabaseConnectionCheck {
  SupabaseConnectionCheck._();

  static Future<void> logProbe() async {
    if (!kDebugMode) return;
    final sw = Stopwatch()..start();
    try {
      final data = await Supabase.instance.client
          .from('races')
          .select('meet, race_date')
          .limit(1);
      debugPrint(
        '[Supabase] 연결 OK — races 샘플 ${data.length}건 (${sw.elapsedMilliseconds}ms)',
      );
    } catch (e, st) {
      debugPrint(
        '[Supabase] 연결/조회 실패: $e (${sw.elapsedMilliseconds}ms)\n$st',
      );
    } finally {
      sw.stop();
    }
  }
}
