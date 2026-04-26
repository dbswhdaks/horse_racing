import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/services/kra_api_service.dart';
import '../../../core/services/kra_video_service.dart';
import '../../../core/services/ml_api_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/local_predictor.dart';
import '../../../models/race.dart';
import '../../../models/race_entry.dart';
import '../../../models/race_result.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';

final supabaseServiceProvider = Provider((ref) => SupabaseService());
final kraApiServiceProvider = Provider((ref) => KraApiService());
final kraVideoServiceProvider = Provider((ref) => KraVideoService());
final mlApiServiceProvider = Provider((ref) => MlApiService());

final raceVideoLinksProvider =
    FutureProvider.family<
      RaceVideoLinks,
      ({String meet, String date, int raceNo})
    >((ref, params) async {
      final service = ref.read(kraVideoServiceProvider);
      return service.getRaceVideoLinks(
        meet: params.meet,
        date: params.date,
        raceNo: params.raceNo,
      );
    });

final selectedMeetProvider = StateProvider<String>((ref) => '1');
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

String formatDateParam(DateTime date) => DateFormat('yyyyMMdd').format(date);

Future<T> _withTimeout<T>(
  Future<T> future,
  Duration timeout,
  T fallback,
) async {
  try {
    return await future.timeout(timeout);
  } catch (_) {
    return fallback;
  }
}

// ── Races: Supabase first → KRA API fallback ──

final racePlanProvider =
    FutureProvider.family<List<Race>, ({String meet, String? date})>((
      ref,
      params,
    ) async {
      final supa = ref.read(supabaseServiceProvider);
      final races = await _withTimeout<List<Race>>(
        supa.getRaces(meet: params.meet, raceDate: params.date),
        const Duration(seconds: 2),
        const [],
      );
      if (races.isNotEmpty) return races;

      final kra = ref.read(kraApiServiceProvider);
      return _withTimeout<List<Race>>(
        kra.getRacePlan(meet: params.meet, rcDate: params.date),
        const Duration(seconds: 5),
        const [],
      );
    });

// ── Entries: Supabase first → KRA API fallback ──

final raceStartListProvider =
    FutureProvider.family<
      List<RaceEntry>,
      ({String meet, String? date, int? raceNo})
    >((ref, params) async {
      final supa = ref.read(supabaseServiceProvider);
      final entries = await _withTimeout<List<RaceEntry>>(
        supa.getEntries(
          meet: params.meet,
          raceDate: params.date,
          raceNo: params.raceNo,
        ),
        const Duration(seconds: 3),
        const [],
      );
      if (entries.isNotEmpty) {
        debugPrint(
          '[ENTRIES] Supabase에서 ${entries.length}건 로드 '
          '(첫 항목: ${entries.first.horseNo}번 ${entries.first.horseName} '
          '기수=${entries.first.jockeyName})',
        );
        return entries;
      }

      final kra = ref.read(kraApiServiceProvider);
      final kraEntries = await _withTimeout<List<RaceEntry>>(
        kra.getRaceStartList(
          meet: params.meet,
          rcDate: params.date,
          rcNo: params.raceNo,
        ),
        const Duration(seconds: 6),
        const [],
      );
      if (kraEntries.isNotEmpty) {
        debugPrint(
          '[ENTRIES] KRA API에서 ${kraEntries.length}건 로드 '
          '(첫 항목: ${kraEntries.first.horseNo}번 ${kraEntries.first.horseName} '
          '기수=${kraEntries.first.jockeyName})',
        );
      }
      return kraEntries;
    });

// ── 경주별 두수: 날짜 전체 출전표에서 경주별 카운트 ──

final raceHeadCountProvider =
    FutureProvider.family<Map<int, int>, ({String meet, String date})>((
      ref,
      params,
    ) async {
      final entries = await ref.read(
        raceStartListProvider((
          meet: params.meet,
          date: params.date,
          raceNo: null,
        )).future,
      );

      final counts = <int, int>{};
      for (final e in entries) {
        counts[e.raceNo] = (counts[e.raceNo] ?? 0) + 1;
      }
      return counts;
    });

// ── Results: Supabase first → KRA API fallback ──

final raceResultProvider =
    FutureProvider.family<
      List<RaceResult>,
      ({String meet, String? date, int? raceNo})
    >((ref, params) async {
      debugPrint(
        '[RESULT] 조회 시작: meet=${params.meet}, '
        'date=${params.date}, raceNo=${params.raceNo}',
      );

      final supa = ref.read(supabaseServiceProvider);

      // 1) Supabase: race_no 필터 포함 조회
      try {
        final results = await supa.getResults(
          meet: params.meet,
          raceDate: params.date,
          raceNo: params.raceNo,
        );
        debugPrint('[RESULT] Supabase(raceNo필터): ${results.length}건');
        if (results.isNotEmpty) return results;
      } catch (e) {
        debugPrint('[RESULT] Supabase 실패: $e');
      }

      // 2) Supabase: race_no=0 데이터 대비 → 출마표 마명으로 매칭
      if (params.raceNo != null) {
        try {
          final allResults = await supa.getResults(
            meet: params.meet,
            raceDate: params.date,
          );
          if (allResults.isNotEmpty) {
            final entries = await ref.read(
              raceStartListProvider((
                meet: params.meet,
                date: params.date,
                raceNo: params.raceNo,
              )).future,
            );
            if (entries.isNotEmpty) {
              final horseNames = entries.map((e) => e.horseName).toSet();
              final matched = allResults
                  .where((r) => horseNames.contains(r.horseName))
                  .toList();
              debugPrint(
                '[RESULT] 마명 매칭: 전체 ${allResults.length}건 중 '
                '${matched.length}건 매칭 (출마표 ${entries.length}두)',
              );
              if (matched.isNotEmpty) return matched;
            }
          }
        } catch (e) {
          debugPrint('[RESULT] Supabase 마명매칭 실패: $e');
        }
      }

      // 3) KRA API fallback
      final kra = ref.read(kraApiServiceProvider);
      try {
        final results = await kra.getRaceResult(
          meet: params.meet,
          rcDate: params.date,
          rcNo: params.raceNo,
        );
        debugPrint('[RESULT] KRA API: ${results.length}건');
        if (results.isNotEmpty) return results;
      } catch (e) {
        debugPrint('[RESULT] KRA API 실패: $e');
      }

      debugPrint('[RESULT] 모든 소스에서 결과 없음');
      throw Exception('경주결과를 가져올 수 없습니다');
    });

// ── Odds: Supabase first → KRA API fallback ──

final oddsProvider =
    FutureProvider.family<
      List<Odds>,
      ({String meet, String? date, int? raceNo})
    >((ref, params) async {
      final supa = ref.read(supabaseServiceProvider);
      final odds = await _withTimeout<List<Odds>>(
        supa.getOdds(
          meet: params.meet,
          raceDate: params.date,
          raceNo: params.raceNo,
        ),
        const Duration(seconds: 3),
        const [],
      );
      if (odds.isNotEmpty) return odds;

      final kra = ref.read(kraApiServiceProvider);
      return _withTimeout<List<Odds>>(
        kra.getOddInfo(
          meet: params.meet,
          rcDate: params.date,
          rcNo: params.raceNo,
        ),
        const Duration(seconds: 6),
        const [],
      );
    });

// ── Predictions: Supabase place model → Local place model → ML fallback ──

final predictionProvider =
    FutureProvider.family<
      PredictionReport?,
      ({String meet, String date, int raceNo})
    >((ref, params) async {
      List<RaceEntry>? entriesCache;
      List<Odds>? oddsCache;
      Future<List<RaceEntry>> loadEntries() async {
        if (entriesCache != null) return entriesCache!;
        entriesCache = await ref.read(
          raceStartListProvider((
            meet: params.meet,
            date: params.date,
            raceNo: params.raceNo,
          )).future,
        );
        return entriesCache!;
      }

      Future<List<Odds>> loadOdds() async {
        if (oddsCache != null) return oddsCache!;
        final supa = ref.read(supabaseServiceProvider);
        var odds = await _withTimeout<List<Odds>>(
          supa.getOdds(
            meet: params.meet,
            raceDate: params.date,
            raceNo: params.raceNo,
          ),
          const Duration(seconds: 3),
          const [],
        );
        if (odds.isNotEmpty) {
          oddsCache = odds;
          return odds;
        }
        final kra = ref.read(kraApiServiceProvider);
        odds = await _withTimeout<List<Odds>>(
          kra.getOddInfo(
            meet: params.meet,
            rcDate: params.date,
            rcNo: params.raceNo,
          ),
          const Duration(seconds: 6),
          const [],
        );
        oddsCache = odds;
        return odds;
      }

      // 1) Supabase
      final supa = ref.read(supabaseServiceProvider);
      try {
        final report = await supa.getPredictions(
          meet: params.meet,
          raceDate: params.date,
          raceNo: params.raceNo,
        );
        if (report != null && report.predictions.isNotEmpty) {
          final entries = await loadEntries();
          if (report.modelVersion == LocalPredictor.modelVersion &&
              (entries.isEmpty || _isPredictionAligned(report, entries))) {
            return report;
          }
          debugPrint(
            '[PRED] Supabase 예측 무시: model=${report.modelVersion}, '
            '예측 ${report.predictions.length}건, 출마표 ${entries.length}두',
          );
        }
      } catch (_) {}

      // 2) Local place model from entry data
      try {
        final entries = await loadEntries();
        if (entries.isNotEmpty) {
          final odds = await loadOdds();
          return LocalPredictor.generate(
            meet: params.meet,
            date: params.date,
            raceNo: params.raceNo,
            entries: entries,
            odds: odds,
          );
        }
      } catch (_) {}

      // 3) ML Backend fallback only when entry data is unavailable
      try {
        final mlApi = ref.read(mlApiServiceProvider);
        final remote = await mlApi.getPrediction(
          meet: params.meet,
          date: params.date,
          raceNo: params.raceNo,
        );
        if (remote != null && remote.predictions.isNotEmpty) {
          final entries = await loadEntries();
          if (entries.isEmpty || _isPredictionAligned(remote, entries)) {
            return remote;
          }
          debugPrint(
            '[PRED] ML 예측 말 수/마번 불일치: '
            '${remote.predictions.length}건, 출마표 ${entries.length}두',
          );
        }
      } catch (_) {}

      return null;
    });

bool _isPredictionAligned(PredictionReport report, List<RaceEntry> entries) {
  final entryHorseNos = entries.map((entry) => entry.horseNo).toSet();
  final predictionHorseNos = report.predictions
      .map((prediction) => prediction.horseNo)
      .where((horseNo) => horseNo > 0)
      .toSet();

  if (entryHorseNos.isEmpty || predictionHorseNos.isEmpty) return false;
  if (!entryHorseNos.containsAll(predictionHorseNos)) return false;

  final minimumCoverage = entries.length <= 7
      ? entries.length
      : entries.length - 1;
  return predictionHorseNos.length >= minimumCoverage;
}

// ── Horse History: Supabase → KRA API (현재 경마장 12개월 + 타 경마장 6개월) ──

final horseResultsProvider =
    FutureProvider.family<List<RaceResult>, ({String meet, String horseName})>((
      ref,
      params,
    ) async {
      // 1) Supabase
      final supa = ref.read(supabaseServiceProvider);
      try {
        final results = await supa.getHorseResults(horseName: params.horseName);
        if (results.isNotEmpty) return results;
      } catch (_) {}

      // 2) KRA API — 현재 경마장 12개월 우선, 타 경마장 6개월 보조
      final kra = ref.read(kraApiServiceProvider);
      final now = DateTime.now();
      final allResults = <RaceResult>[];
      final seenKeys = <String>{};
      final primaryMeet = params.meet;
      final otherMeets = [
        '1',
        '2',
        '3',
      ].where((m) => m != primaryMeet).toList();

      Future<Set<String>> collectDates(String meet, int months) async {
        final dates = <String>{};
        final futures = <Future<List<String>>>[];
        for (int offset = 0; offset <= months; offset++) {
          final target = DateTime(now.year, now.month - offset, 1);
          final monthStr = DateFormat('yyyyMM').format(target);
          futures.add(
            kra
                .getRacePlan(meet: meet, rcMonth: monthStr)
                .then((races) => races.map((r) => r.raceDate).toSet().toList())
                .catchError((_) => <String>[]),
          );
        }
        final results = await Future.wait(futures);
        for (final list in results) {
          dates.addAll(list);
        }
        return dates;
      }

      Future<void> scanDates(String meet, Set<String> dates) async {
        final jobList = dates.toList();
        for (int start = 0; start < jobList.length; start += 5) {
          final batch = jobList.skip(start).take(5).map((dt) async {
            try {
              final dayResults = await kra.getRaceResult(
                meet: meet,
                rcDate: dt,
              );
              for (final r in dayResults) {
                if (r.horseName == params.horseName) {
                  final key = '${r.raceDate}_${r.raceNo}_${r.horseNo}_$meet';
                  if (seenKeys.add(key)) allResults.add(r);
                }
              }
            } catch (_) {}
          });
          await Future.wait(batch);
        }
      }

      // (a) 현재 경마장: 12개월 스캔
      final primaryDates = await collectDates(primaryMeet, 12);
      debugPrint('[HORSE] $primaryMeet 경마장 ${primaryDates.length}개 경마일 스캔');
      await scanDates(primaryMeet, primaryDates);
      debugPrint('[HORSE] $primaryMeet 스캔 완료 → ${allResults.length}건');

      // (b) 타 경마장: 6개월 스캔 (병렬)
      final otherDateFutures = otherMeets
          .map((m) => collectDates(m, 6))
          .toList();
      final otherDateSets = await Future.wait(otherDateFutures);
      for (int i = 0; i < otherMeets.length; i++) {
        if (otherDateSets[i].isNotEmpty) {
          await scanDates(otherMeets[i], otherDateSets[i]);
        }
      }

      debugPrint('[HORSE] 전체 스캔 완료 → 총 ${allResults.length}건');
      allResults.sort((a, b) => b.raceDate.compareTo(a.raceDate));
      return allResults;
    });
