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

final FutureProviderFamily<
  List<RaceEntry>,
  ({String meet, String? date, int? raceNo})
>
raceStartListProvider =
    FutureProvider.family<
      List<RaceEntry>,
      ({String meet, String? date, int? raceNo})
    >((ref, params) async {
      if (params.date != null && params.raceNo != null) {
        final dayEntries = ref
            .read(
              raceStartListProvider((
                meet: params.meet,
                date: params.date,
                raceNo: null,
              )),
            )
            .valueOrNull;
        if (dayEntries != null && dayEntries.isNotEmpty) {
          final cachedEntries = dayEntries
              .where((entry) => entry.raceNo == params.raceNo)
              .toList();
          if (cachedEntries.isNotEmpty) return cachedEntries;
        }
      }

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

      // 1) Supabase: race_no 필터 포함 조회 — 짧은 타임아웃으로 빠르게 실패시킨다.
      try {
        final results = await supa
            .getResults(
              meet: params.meet,
              raceDate: params.date,
              raceNo: params.raceNo,
            )
            .timeout(const Duration(seconds: 3));
        debugPrint('[RESULT] Supabase(raceNo필터): ${results.length}건');
        if (results.isNotEmpty) return results;
      } catch (e) {
        debugPrint('[RESULT] Supabase 실패: $e');
      }

      // 2) Supabase: race_no=0 데이터 대비 → 출마표 마명으로 매칭
      //    1) 이 비어있을 때만 시도하므로 추가 비용은 평균적으로 미미하다.
      if (params.raceNo != null) {
        try {
          final allResults = await supa
              .getResults(meet: params.meet, raceDate: params.date)
              .timeout(const Duration(seconds: 3));
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
        final results = await kra
            .getRaceResult(
              meet: params.meet,
              rcDate: params.date,
              rcNo: params.raceNo,
            )
            .timeout(const Duration(seconds: 6));
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
      // entries/odds 를 직렬이 아닌 병렬로 미리 시작해 두면 Supabase 예측과
      // 동시에 받아올 수 있어 체감 로딩 시간이 크게 줄어든다.
      final entriesFuture = ref.read(
        raceStartListProvider((
          meet: params.meet,
          date: params.date,
          raceNo: params.raceNo,
        )).future,
      );
      // odds 는 LocalPredictor 의 시장(배당) 신호에 사용된다. 비어 있으면
      // 모든 말의 점수가 평탄해져 AI 승률이 거의 같은 값으로 나올 수 있다.
      // 라이브 배당(Supabase → KRA)이 없으면, 이미 캐시된 경주결과로부터 최종
      // 배당을 합성한다. (캐시 미스 시에는 무거운 fetch 를 새로 트리거하지 않는다.)
      Future<List<Odds>> loadOdds() async {
        final supa = ref.read(supabaseServiceProvider);
        var odds = await _withTimeout<List<Odds>>(
          supa.getOdds(
            meet: params.meet,
            raceDate: params.date,
            raceNo: params.raceNo,
          ),
          const Duration(seconds: 2),
          const [],
        );
        if (odds.isNotEmpty) return odds;
        final kra = ref.read(kraApiServiceProvider);
        odds = await _withTimeout<List<Odds>>(
          kra.getOddInfo(
            meet: params.meet,
            rcDate: params.date,
            rcNo: params.raceNo,
          ),
          const Duration(seconds: 3),
          const [],
        );
        if (odds.isNotEmpty) return odds;

        // 라이브 배당이 모두 비어 있는 경우 → 종료된 경주의 결과 최종배당을 합성한다.
        // 이미 다른 화면에서 raceResultProvider 가 로드된 경우엔 캐시를 즉시 사용해
        // 추가 비용 없이 시장 신호를 확보한다. 캐시 미스 시에는 짧은 타임아웃으로
        // 시도하고, 실패하면 빈 배열로 폴백한다.
        final resultsCached = ref
            .read(
              raceResultProvider((
                meet: params.meet,
                date: params.date,
                raceNo: params.raceNo,
              )),
            )
            .valueOrNull;
        List<RaceResult> results = resultsCached ?? const [];
        if (results.isEmpty) {
          try {
            results = await ref
                .read(
                  raceResultProvider((
                    meet: params.meet,
                    date: params.date,
                    raceNo: params.raceNo,
                  )).future,
                )
                .timeout(const Duration(seconds: 4));
          } catch (_) {}
        }
        if (results.isEmpty) return const [];

        final entries = await ref.read(
          raceStartListProvider((
            meet: params.meet,
            date: params.date,
            raceNo: params.raceNo,
          )).future,
        );
        final nameToHorseNo = <String, int>{
          for (final e in entries)
            if (e.horseName.isNotEmpty) e.horseName: e.horseNo,
        };
        final synthesized = <Odds>[];
        for (final r in results) {
          final hno = nameToHorseNo[r.horseName] ?? r.horseNo;
          if (hno <= 0) continue;
          if (r.winOdds > 0) {
            synthesized.add(
              Odds(
                betType: 'WIN',
                horseNo1: hno,
                horseNo2: 0,
                horseNo3: 0,
                rate: r.winOdds,
              ),
            );
          }
          if (r.placeOdds > 0) {
            synthesized.add(
              Odds(
                betType: 'PLC',
                horseNo1: hno,
                horseNo2: 0,
                horseNo3: 0,
                rate: r.placeOdds,
              ),
            );
          }
        }
        return synthesized;
      }

      final oddsFuture = loadOdds();

      // 1) Supabase — 출주표가 로드되어 정합성이 검증된 경우에만 사용한다.
      final supa = ref.read(supabaseServiceProvider);
      try {
        final report = await supa.getPredictions(
          meet: params.meet,
          raceDate: params.date,
          raceNo: params.raceNo,
        );
        if (report != null && report.predictions.isNotEmpty) {
          final entries = await entriesFuture;
          if (entries.isNotEmpty &&
              report.modelVersion == LocalPredictor.modelVersion &&
              _isPredictionAligned(report, entries)) {
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
        final entries = await entriesFuture;
        if (entries.isNotEmpty) {
          final odds = await oddsFuture;
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
          final entries = await entriesFuture;
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

String _normalizeHorseName(String raw) {
  // 괄호 안 부속(국적 등)·공백·하이픈을 제거해 표기 차이에 둔감하게 만든다.
  return raw
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .replaceAll(RegExp(r'[\s\-_]'), '')
      .trim();
}

bool _isPredictionAligned(PredictionReport report, List<RaceEntry> entries) {
  final entryNameByHorseNo = <int, String>{
    for (final entry in entries)
      entry.horseNo: _normalizeHorseName(entry.horseName),
  };
  final entryHorseNos = entryNameByHorseNo.keys.toSet();
  final predictionHorseNos = report.predictions
      .map((prediction) => prediction.horseNo)
      .where((horseNo) => horseNo > 0)
      .toSet();

  if (entryHorseNos.isEmpty || predictionHorseNos.isEmpty) return false;
  if (!entryHorseNos.containsAll(predictionHorseNos)) return false;

  // horseNo 가 같아도 horseName 이 다르면 다른 경주/오래된 예측이므로 폐기한다.
  // 양쪽 모두 이름이 채워져 있을 때만, 그리고 정규화한 형태로 비교한다.
  for (final prediction in report.predictions) {
    final predName = _normalizeHorseName(prediction.horseName);
    final entryName = entryNameByHorseNo[prediction.horseNo];
    if (predName.isEmpty || entryName == null || entryName.isEmpty) continue;
    if (predName != entryName) {
      debugPrint(
        '[PRED] horseName 불일치: horseNo=${prediction.horseNo} '
        'pred="$predName" vs entry="$entryName" → 정렬되지 않음으로 판정',
      );
      return false;
    }
  }

  final minimumCoverage = entries.length <= 7
      ? entries.length
      : entries.length - 1;
  return predictionHorseNos.length >= minimumCoverage;
}

// ── Race 단위 말 통계 (전적/승률/입상률) 배치 조회 ──
// Supabase 만 사용해 빠르게 끝낸다. 일부 말이 없거나 타임아웃이면
// 해당 말은 (0,0,0) 으로 채워 카드가 영원히 로딩되지 않게 한다.

typedef HorseStatsSnapshot = ({int totalRaces, int winCount, int placeCount});

final raceHorseStatsProvider =
    FutureProvider.family<
      Map<String, HorseStatsSnapshot>,
      ({String meet, String date, int raceNo})
    >((ref, params) async {
      final entries = await ref.watch(
        raceStartListProvider((
          meet: params.meet,
          date: params.date,
          raceNo: params.raceNo,
        )).future,
      );
      if (entries.isEmpty) return const {};

      final supa = ref.read(supabaseServiceProvider);
      final stats = <String, HorseStatsSnapshot>{};

      // 1) 출주표(KRA)에 이미 전적이 들어있는 말은 그 값을 그대로 채워 둔다.
      //    별도 fetch 없이 즉시 화면을 그릴 수 있어 가장 큰 지연을 제거한다.
      final entriesNeedingFetch = <RaceEntry>[];
      for (final e in entries) {
        if (e.horseName.isEmpty) continue;
        if (e.totalRaces > 0) {
          stats[e.horseName] = (
            totalRaces: e.totalRaces,
            winCount: e.winCount,
            placeCount: e.placeCount,
          );
        } else {
          entriesNeedingFetch.add(e);
        }
      }

      if (entriesNeedingFetch.isEmpty) return stats;

      // 2) 출주표에 전적이 비어 있는 말만 Supabase 에서 가볍게 보강한다.
      //    horseResultsProvider 의 12개월 KRA 스캔(최대 25초)은 호출하지 않는다.
      //    상세 전적은 말 상세 화면에서 별도로 로드된다.
      await Future.wait(
        entriesNeedingFetch.map((e) async {
          List<RaceResult> results = const [];
          try {
            results = await supa
                .getHorseResults(horseName: e.horseName)
                .timeout(const Duration(seconds: 3));
          } catch (_) {}
          final ranked = results.where((r) => r.rank > 0).toList();
          stats[e.horseName] = (
            totalRaces: ranked.length,
            winCount: ranked.where((r) => r.rank == 1).length,
            placeCount:
                ranked.where((r) => r.rank == 2 || r.rank == 3).length,
          );
        }),
      );

      return stats;
    });

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
