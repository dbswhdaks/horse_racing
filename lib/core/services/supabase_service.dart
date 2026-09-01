import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/prediction_constants.dart';
import 'entry_features.dart';
import '../../models/race.dart';
import '../../models/race_entry.dart';
import '../../models/race_result.dart';
import '../../models/odds.dart';
import '../../models/prediction.dart';

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  // ── Races ──

  Future<List<Race>> getRaces({required String meet, String? raceDate}) async {
    var query = _client.from('races').select().eq('meet', meet);
    if (raceDate != null) {
      query = query.eq('race_date', raceDate);
    }
    final data = await query.order('race_no');
    final rows = _normalizeRows(data);
    return rows
        .map<Race>(
          (row) => Race(
            meet: row['meet']?.toString() ?? '',
            meetName: _meetName(row['meet']?.toString() ?? ''),
            raceDate: row['race_date']?.toString() ?? '',
            raceNo: (row['race_no'] as num?)?.toInt() ?? 0,
            startTime: row['start_time']?.toString() ?? '',
            distance: (row['distance'] as num?)?.toInt() ?? 0,
            gradeCondition: row['grade_condition']?.toString() ?? '',
            raceName: row['race_name']?.toString() ?? '',
            ageCondition: row['age_condition']?.toString() ?? '',
            sexCondition: row['sex_condition']?.toString() ?? '',
            weightCondition: row['weight_condition']?.toString() ?? '',
            prize1: (row['prize1'] as num?)?.toInt() ?? 0,
            prize2: (row['prize2'] as num?)?.toInt() ?? 0,
            prize3: (row['prize3'] as num?)?.toInt() ?? 0,
            headCount: (row['head_count'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  // ── Entries ──

  Future<List<RaceEntry>> getEntries({
    required String meet,
    String? raceDate,
    int? raceNo,
  }) async {
    var query = _client.from('race_entries').select().eq('meet', meet);
    if (raceDate != null) query = query.eq('race_date', raceDate);
    if (raceNo != null) query = query.eq('race_no', raceNo);
    final data = await query.order('horse_no');
    return data
        .map<RaceEntry>(
          (row) => RaceEntry(
            raceNo: row['race_no'] ?? 0,
            horseNo: row['horse_no'] ?? 0,
            horseName: row['horse_name'] ?? '',
            birthPlace: row['birth_place'] ?? '',
            sex: row['sex'] ?? '',
            age: row['age'] ?? 0,
            jockeyName: row['jockey_name'] ?? '',
            trainerName: row['trainer_name'] ?? '',
            ownerName: row['owner_name'] ?? '',
            weight: (row['weight'] as num?)?.toDouble() ?? 0,
            rating: (row['rating'] as num?)?.toDouble() ?? 0,
            totalPrize: row['total_prize'] ?? 0,
            recentPrize: row['recent_prize'] ?? 0,
            winCount: row['win_count'] ?? 0,
            placeCount: row['place_count'] ?? 0,
            totalRaces: row['total_races'] ?? 0,
            horseWeight: (row['horse_weight'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  // ── Results ──

  Future<List<RaceResult>> getResults({
    required String meet,
    String? raceDate,
    int? raceNo,
  }) async {
    var query = _client.from('race_results').select().eq('meet', meet);
    if (raceDate != null) query = query.eq('race_date', raceDate);
    if (raceNo != null) query = query.eq('race_no', raceNo);
    final data = await query.order('rank');
    return data
        .map<RaceResult>(
          (row) => RaceResult(
            raceNo: row['race_no'] ?? 0,
            rank: row['rank'] ?? 0,
            horseNo: row['horse_no'] ?? 0,
            horseName: row['horse_name'] ?? '',
            jockeyName: row['jockey_name'] ?? '',
            trainerName: row['trainer_name'] ?? '',
            raceTime: row['race_time'] ?? '',
            weight: (row['weight'] as num?)?.toDouble() ?? 0,
            horseWeight: (row['horse_weight'] as num?)?.toDouble() ?? 0,
            rankDiff: row['rank_diff'] ?? '',
            winOdds: (row['win_odds'] as num?)?.toDouble() ?? 0,
            placeOdds: (row['place_odds'] as num?)?.toDouble() ?? 0,
            s1f: row['s1f'] ?? '',
            g3f: row['g3f'] ?? '',
            passOrder: row['pass_order'] ?? '',
            distance: row['distance'] ?? 0,
            raceDate: row['race_date'] ?? '',
            meet: row['meet'] ?? '',
          ),
        )
        .toList();
  }

  // ── Horse History ──

  Future<Map<String, ({int totalRaces, int winCount, int placeCount})>>
  getHorseStatsBatch({required Iterable<String> horseNames}) async {
    final names = horseNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) return const {};

    final data = <Map<String, dynamic>>[];
    const pageSize = 1000;
    var offset = 0;
    while (true) {
      final page = _normalizeRows(
        await _client
            .from('race_results')
            .select('horse_name,rank')
            .inFilter('horse_name', names)
            .gt('rank', 0)
            .range(offset, offset + pageSize - 1),
      );
      data.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }

    final totals = <String, ({int totalRaces, int winCount, int placeCount})>{};
    for (final row in data) {
      final horseName = row['horse_name']?.toString().trim() ?? '';
      final rank = (row['rank'] as num?)?.toInt() ?? 0;
      if (horseName.isEmpty || rank <= 0) continue;
      final current = totals[horseName];
      totals[horseName] = (
        totalRaces: (current?.totalRaces ?? 0) + 1,
        winCount: (current?.winCount ?? 0) + (rank == 1 ? 1 : 0),
        placeCount:
            (current?.placeCount ?? 0) + (rank == 2 || rank == 3 ? 1 : 0),
      );
    }
    return totals;
  }

  // ── As-of Entry Features ──

  /// 출전마·기수의 **경주일 이전** 성적만으로 as-of 서브스코어를 계산합니다.
  ///
  /// 계산식은 `backend/entry_features.py` 와 동일하며, 조회 실패 시 호출부가
  /// 중립값으로 폴백할 수 있도록 빈 맵을 반환합니다.
  Future<Map<int, EntryFeatureScores>> getEntryFeaturesBatch({
    required String raceDate,
    required int distance,
    required List<RaceEntry> entries,
  }) async {
    if (entries.isEmpty) return const {};

    final horseNames = entries
        .map((e) => e.horseName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    final jockeyNames = entries
        .map((e) => e.jockeyName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (horseNames.isEmpty && jockeyNames.isEmpty) return const {};

    // 기수 점수는 최근 1년 입상률만 쓰므로 말 이력보다 좁게 조회해 응답을 줄입니다.
    final horseSince = _shiftDate(raceDate, -_horseHistoryDays);
    final jockeySince = _shiftDate(raceDate, -jockeyWindowDays);
    if (horseSince == null || jockeySince == null) return const {};

    // 두 조회는 서로 의존하지 않으므로 병렬로 보냅니다.
    final fetched = await Future.wait([
      horseNames.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : _fetchPastRuns(
              column: 'horse_name',
              values: horseNames,
              since: horseSince,
              until: raceDate,
            ),
      jockeyNames.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : _fetchPastRuns(
              column: 'jockey_name',
              values: jockeyNames,
              since: jockeySince,
              until: raceDate,
            ),
    ]);
    final horseRows = fetched[0];
    if (horseRows.isEmpty && fetched[1].isEmpty) return const {};

    // 같은 경주 행이 말·기수 양쪽 조회에 중복으로 잡히므로 한 번만 남깁니다.
    final deduped = <String, Map<String, dynamic>>{};
    for (final row in [...horseRows, ...fetched[1]]) {
      final key =
          '${row['meet']}_${row['race_date']}_${row['race_no']}_${row['horse_no']}';
      deduped[key] = row;
    }

    // 두수는 착순 백분위에만 쓰이고 그 계산은 말 이력에서만 하므로,
    // 기수 이력의 날짜까지 조회할 필요가 없습니다.
    final fieldSizes = await _fetchFieldSizes(horseRows);

    final index = AsOfFeatureIndex(
      deduped.values.map((row) {
        final rowDate = row['race_date']?.toString() ?? '';
        final raceNo = (row['race_no'] as num?)?.toInt() ?? 0;
        return PastRunRecord(
          raceDate: rowDate,
          raceNo: raceNo,
          horseName: row['horse_name']?.toString() ?? '',
          jockeyName: row['jockey_name']?.toString() ?? '',
          rank: (row['rank'] as num?)?.toInt() ?? 0,
          fieldSize: fieldSizes['${row['meet']}_${rowDate}_$raceNo'] ?? 0,
          distance: (row['distance'] as num?)?.toInt() ?? 0,
          horseWeight: (row['horse_weight'] as num?)?.toDouble() ?? 0,
        );
      }),
    );

    return {
      for (final entry in entries)
        entry.horseNo: index.featuresFor(
          raceDate: raceDate,
          horseName: entry.horseName,
          jockeyName: entry.jockeyName,
          distance: distance,
          horseWeight: entry.horseWeight,
        ),
    };
  }

  /// 말 이력 조회 기간(일). 거리 적성 표본을 모으려면 1년보다 길어야 합니다.
  static const _horseHistoryDays = 730;

  Future<List<Map<String, dynamic>>> _fetchPastRuns({
    required String column,
    required List<String> values,
    required String since,
    required String until,
  }) async {
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = _normalizeRows(
        await _client
            .from('race_results')
            .select(
              'meet,race_date,race_no,horse_no,horse_name,jockey_name,'
              'rank,horse_weight,distance',
            )
            .inFilter(column, values)
            .gte('race_date', since)
            .lt('race_date', until)
            .gt('rank', 0)
            .range(offset, offset + pageSize - 1),
      );
      rows.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return rows;
  }

  /// 착순 백분위 계산에 필요한 경주별 출주 두수를 `races.head_count` 에서 얻습니다.
  Future<Map<String, int>> _fetchFieldSizes(
    Iterable<Map<String, dynamic>> pastRuns,
  ) async {
    final dates = pastRuns
        .map((row) => row['race_date']?.toString() ?? '')
        .where((date) => date.length == 8)
        .toSet()
        .toList();
    if (dates.isEmpty) return const {};

    final rows = _normalizeRows(
      await _client
          .from('races')
          .select('meet,race_date,race_no,head_count')
          .inFilter('race_date', dates),
    );

    return {
      for (final row in rows)
        '${row['meet']}_${row['race_date']}_${row['race_no']}':
            (row['head_count'] as num?)?.toInt() ?? 0,
    };
  }

  /// `YYYYMMDD` 문자열을 [days] 만큼 이동합니다. 형식이 어긋나면 null.
  static String? _shiftDate(String raceDate, int days) {
    final text = raceDate.trim();
    if (text.length != 8) return null;
    final year = int.tryParse(text.substring(0, 4));
    final month = int.tryParse(text.substring(4, 6));
    final day = int.tryParse(text.substring(6, 8));
    if (year == null || month == null || day == null) return null;

    final shifted = DateTime.utc(year, month, day).add(Duration(days: days));
    return '${shifted.year.toString().padLeft(4, '0')}'
        '${shifted.month.toString().padLeft(2, '0')}'
        '${shifted.day.toString().padLeft(2, '0')}';
  }

  Future<List<RaceResult>> getHorseResults({
    required String horseName,
    String? meet,
  }) async {
    var query = _client
        .from('race_results')
        .select()
        .eq('horse_name', horseName);
    if (meet != null) query = query.eq('meet', meet);
    final data = await query.order('race_date', ascending: false).limit(200);
    return data
        .map<RaceResult>(
          (row) => RaceResult(
            raceNo: row['race_no'] ?? 0,
            rank: row['rank'] ?? 0,
            horseNo: row['horse_no'] ?? 0,
            horseName: row['horse_name'] ?? '',
            jockeyName: row['jockey_name'] ?? '',
            trainerName: row['trainer_name'] ?? '',
            raceTime: row['race_time'] ?? '',
            weight: (row['weight'] as num?)?.toDouble() ?? 0,
            horseWeight: (row['horse_weight'] as num?)?.toDouble() ?? 0,
            rankDiff: row['rank_diff'] ?? '',
            winOdds: (row['win_odds'] as num?)?.toDouble() ?? 0,
            placeOdds: (row['place_odds'] as num?)?.toDouble() ?? 0,
            s1f: row['s1f'] ?? '',
            g3f: row['g3f'] ?? '',
            passOrder: row['pass_order'] ?? '',
            distance: row['distance'] ?? 0,
            raceDate: row['race_date'] ?? '',
            meet: row['meet'] ?? '',
          ),
        )
        .toList();
  }

  // ── Predictions ──

  Future<PredictionReport?> getPredictions({
    required String meet,
    required String raceDate,
    required int raceNo,
  }) async {
    final data = await _client
        .from('predictions')
        .select()
        .eq('meet', meet)
        .eq('race_date', raceDate)
        .eq('race_no', raceNo)
        .order('created_at', ascending: false);

    final rows = _selectPredictionRows(_normalizeRows(data));
    if (rows.isEmpty) return null;

    final predictions = rows.map<Prediction>((row) {
      final tags =
          (row['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [];
      final importance =
          (row['feature_importance'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          {};

      return Prediction(
        horseNo: row['horse_no'] ?? 0,
        horseName: row['horse_name'] ?? '',
        jockeyName: row['jockey_name'] ?? '',
        winProbability: (row['win_probability'] as num?)?.toDouble() ?? 0,
        placeProbability: (row['place_probability'] as num?)?.toDouble() ?? 0,
        tags: tags,
        featureImportance: importance,
      );
    }).toList();

    return PredictionReport(
      raceId: '${meet}_${raceDate}_$raceNo',
      raceDate: raceDate,
      meet: meet,
      raceNo: raceNo,
      predictions: predictions,
      modelVersion: rows.first['model_version']?.toString() ?? '',
      generatedAt:
          DateTime.tryParse(rows.first['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  // ── Odds ──

  Future<List<Odds>> getOdds({
    required String meet,
    String? raceDate,
    int? raceNo,
  }) async {
    var query = _client.from('odds').select().eq('meet', meet);
    if (raceDate != null) query = query.eq('race_date', raceDate);
    if (raceNo != null) query = query.eq('race_no', raceNo);
    final data = await query;
    return data
        .map<Odds>(
          (row) => Odds(
            betType: row['bet_type'] ?? '',
            horseNo1: row['horse_no1'] ?? 0,
            horseNo2: row['horse_no2'] ?? 0,
            horseNo3: row['horse_no3'] ?? 0,
            rate: (row['rate'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  static String _meetName(String meet) {
    const names = {'1': '서울', '2': '제주', '3': '부산경남'};
    return names[meet] ?? meet;
  }

  static List<Map<String, dynamic>> _selectPredictionRows(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return const [];

    final byVersion = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final version = row['model_version']?.toString() ?? '';
      byVersion.putIfAbsent(version, () => []).add(row);
    }

    final selectedVersion = PredictionConstants.preferredModelVersions
        .where(byVersion.containsKey)
        .cast<String?>()
        .firstWhere((version) => version != null, orElse: () => null);

    final versionRows = selectedVersion != null
        ? byVersion[selectedVersion]!
        : byVersion.entries.reduce((a, b) {
            final aTime = a.value
                .map(_createdAt)
                .reduce(
                  (current, next) => next.isAfter(current) ? next : current,
                );
            final bTime = b.value
                .map(_createdAt)
                .reduce(
                  (current, next) => next.isAfter(current) ? next : current,
                );
            return bTime.isAfter(aTime) ? b : a;
          }).value;

    final latestByHorseNo = <int, Map<String, dynamic>>{};
    final sortedByCreatedAt = [...versionRows]
      ..sort((a, b) {
        final timeCompare = _createdAt(b).compareTo(_createdAt(a));
        if (timeCompare != 0) return timeCompare;
        return ((b['win_probability'] as num?)?.toDouble() ?? 0).compareTo(
          (a['win_probability'] as num?)?.toDouble() ?? 0,
        );
      });

    for (final row in sortedByCreatedAt) {
      final horseNo = (row['horse_no'] as num?)?.toInt() ?? 0;
      if (horseNo <= 0 || latestByHorseNo.containsKey(horseNo)) continue;
      latestByHorseNo[horseNo] = row;
    }

    return latestByHorseNo.values.toList()..sort((a, b) {
      final winCompare = ((b['win_probability'] as num?)?.toDouble() ?? 0)
          .compareTo((a['win_probability'] as num?)?.toDouble() ?? 0);
      if (winCompare != 0) return winCompare;
      final placeCompare = ((b['place_probability'] as num?)?.toDouble() ?? 0)
          .compareTo((a['place_probability'] as num?)?.toDouble() ?? 0);
      if (placeCompare != 0) return placeCompare;
      final aHorseNo = (a['horse_no'] as num?)?.toInt() ?? 0;
      final bHorseNo = (b['horse_no'] as num?)?.toInt() ?? 0;
      return aHorseNo.compareTo(bHorseNo);
    });
  }

  static DateTime _createdAt(Map<String, dynamic> row) {
    return DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static List<Map<String, dynamic>> _normalizeRows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }
}
