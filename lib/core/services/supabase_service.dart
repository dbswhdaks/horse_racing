import 'package:supabase_flutter/supabase_flutter.dart';
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

    const preferredVersions = [
      'heuristic-place-1.1',
      'heuristic-place-1.0',
      'heuristic-3.1-tuned',
      'heuristic-3.1',
      '1.0',
    ];
    final selectedVersion = preferredVersions
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
