import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/kra_api_service.dart';
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
final mlApiServiceProvider = Provider((ref) => MlApiService());

final selectedMeetProvider = StateProvider<String>((ref) => '1');

// ── Races: Supabase first → KRA API fallback ──

final racePlanProvider =
    FutureProvider.family<List<Race>, ({String meet, String? date})>(
  (ref, params) async {
    final supa = ref.read(supabaseServiceProvider);
    try {
      final races = await supa.getRaces(
        meet: params.meet,
        raceDate: params.date,
      );
      if (races.isNotEmpty) return races;
    } catch (_) {}

    final kra = ref.read(kraApiServiceProvider);
    return kra.getRacePlan(meet: params.meet, rcDate: params.date);
  },
);

// ── Entries: Supabase first → KRA API fallback ──

final raceStartListProvider = FutureProvider.family<List<RaceEntry>,
    ({String meet, String? date, int? raceNo})>(
  (ref, params) async {
    final supa = ref.read(supabaseServiceProvider);
    try {
      final entries = await supa.getEntries(
        meet: params.meet,
        raceDate: params.date,
        raceNo: params.raceNo,
      );
      if (entries.isNotEmpty) return entries;
    } catch (_) {}

    final kra = ref.read(kraApiServiceProvider);
    return kra.getRaceStartList(
      meet: params.meet,
      rcDate: params.date,
      rcNo: params.raceNo,
    );
  },
);

// ── Results: Supabase first → KRA API fallback ──

final raceResultProvider = FutureProvider.family<List<RaceResult>,
    ({String meet, String? date, int? raceNo})>(
  (ref, params) async {
    final supa = ref.read(supabaseServiceProvider);
    try {
      final results = await supa.getResults(
        meet: params.meet,
        raceDate: params.date,
        raceNo: params.raceNo,
      );
      if (results.isNotEmpty) return results;
    } catch (_) {}

    final kra = ref.read(kraApiServiceProvider);
    return kra.getRaceResult(
      meet: params.meet,
      rcDate: params.date,
      rcNo: params.raceNo,
    );
  },
);

// ── Odds: Supabase first → KRA API fallback ──

final oddsProvider = FutureProvider.family<List<Odds>,
    ({String meet, String? date, int? raceNo})>(
  (ref, params) async {
    final supa = ref.read(supabaseServiceProvider);
    try {
      final odds = await supa.getOdds(
        meet: params.meet,
        raceDate: params.date,
        raceNo: params.raceNo,
      );
      if (odds.isNotEmpty) return odds;
    } catch (_) {}

    final kra = ref.read(kraApiServiceProvider);
    return kra.getOddInfo(
      meet: params.meet,
      rcDate: params.date,
      rcNo: params.raceNo,
    );
  },
);

// ── Predictions: Supabase → ML Backend → Local fallback ──

final predictionProvider = FutureProvider.family<PredictionReport?,
    ({String meet, String date, int raceNo})>(
  (ref, params) async {
    // 1) Supabase
    final supa = ref.read(supabaseServiceProvider);
    try {
      final report = await supa.getPredictions(
        meet: params.meet,
        raceDate: params.date,
        raceNo: params.raceNo,
      );
      if (report != null && report.predictions.isNotEmpty) return report;
    } catch (_) {}

    // 2) ML Backend
    final mlApi = ref.read(mlApiServiceProvider);
    final remote = await mlApi.getPrediction(
      meet: params.meet,
      date: params.date,
      raceNo: params.raceNo,
    );
    if (remote != null) return remote;

    // 3) Local fallback from entry data
    try {
      final entries = await ref.read(raceStartListProvider(
        (meet: params.meet, date: params.date, raceNo: params.raceNo),
      ).future);
      if (entries.isNotEmpty) {
        return LocalPredictor.generate(
          meet: params.meet,
          date: params.date,
          raceNo: params.raceNo,
          entries: entries,
        );
      }
    } catch (_) {}

    return null;
  },
);

// ── Horse History: Supabase first → KRA API fallback ──

final horseResultsProvider =
    FutureProvider.family<List<RaceResult>, ({String meet, String horseName})>(
  (ref, params) async {
    final supa = ref.read(supabaseServiceProvider);
    try {
      final results = await supa.getHorseResults(
        horseName: params.horseName,
        meet: params.meet,
      );
      if (results.isNotEmpty) return results;
    } catch (_) {}

    final kra = ref.read(kraApiServiceProvider);
    final results = await kra.getRaceResult(meet: params.meet);
    return results
        .where((r) => r.horseName == params.horseName)
        .toList()
      ..sort((a, b) => b.raceDate.compareTo(a.raceDate));
  },
);
