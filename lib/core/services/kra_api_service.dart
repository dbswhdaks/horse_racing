import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../network/dio_client.dart';
import '../../models/race.dart';
import '../../models/race_entry.dart';
import '../../models/race_result.dart';
import '../../models/odds.dart';

class KraApiService {
  final Dio _dio = DioClient.kra;

  Future<List<Race>> getRacePlan({
    required String meet,
    String? rcDate,
    String? rcMonth,
  }) async {
    final params = <String, dynamic>{'meet': meet};
    if (rcDate != null) params['rc_date'] = rcDate;
    if (rcMonth != null) params['rc_month'] = rcMonth;

    final response = await _dio.get(
      ApiConstants.racePlanPath,
      queryParameters: params,
    );
    return _parseList(response, (json) => Race.fromJson(json));
  }

  /// API26_2 출전표 상세정보
  /// Params: meet, month (MM), day (DD), pageNo, numOfRows
  Future<List<RaceEntry>> getRaceStartList({
    required String meet,
    String? rcDate,
    int? rcNo,
  }) async {
    final params = <String, dynamic>{
      'meet': meet,
      'pageNo': 1,
      'numOfRows': 100,
    };

    if (rcDate != null && rcDate.length == 8) {
      params['month'] = rcDate.substring(4, 6);
      params['day'] = rcDate.substring(6, 8);
    }

    final response = await _dio.get(
      ApiConstants.raceStartListPath,
      queryParameters: params,
    );

    final entries = _parseList(response, (json) => RaceEntry.fromJson(json));

    if (rcNo != null && entries.isNotEmpty) {
      return entries.where((e) => true).toList();
    }
    return entries;
  }

  Future<List<RaceResult>> getRaceResult({
    required String meet,
    String? rcDate,
    int? rcNo,
  }) async {
    final params = <String, dynamic>{
      'meet': meet,
      'pageNo': 1,
      'numOfRows': 100,
    };
    if (rcDate != null && rcDate.length == 8) {
      params['month'] = rcDate.substring(4, 6);
      params['day'] = rcDate.substring(6, 8);
    }
    if (rcNo != null) params['rc_no'] = rcNo;

    final response = await _dio.get(
      ApiConstants.raceResultPath,
      queryParameters: params,
    );
    return _parseList(response, (json) => RaceResult.fromJson(json));
  }

  Future<List<Odds>> getOddInfo({
    required String meet,
    String? rcDate,
    int? rcNo,
  }) async {
    final params = <String, dynamic>{
      'meet': meet,
      'pageNo': 1,
      'numOfRows': 100,
    };
    if (rcDate != null && rcDate.length == 8) {
      params['month'] = rcDate.substring(4, 6);
      params['day'] = rcDate.substring(6, 8);
    }
    if (rcNo != null) params['rc_no'] = rcNo;

    final response = await _dio.get(
      ApiConstants.oddInfoPath,
      queryParameters: params,
    );
    return _parseList(response, (json) => Odds.fromJson(json));
  }

  Future<List<RaceResult>> getAiRaceResult({
    required String rccsCd,
    required String raceDt,
  }) async {
    final params = <String, dynamic>{
      'rccrs_cd': rccsCd,
      'race_dt': raceDt,
    };

    final response = await _dio.get(
      ApiConstants.aiRaceResultPath,
      queryParameters: params,
    );
    return _parseList(response, (json) => RaceResult.fromJson(json));
  }

  List<T> _parseList<T>(
    Response response,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final data = response.data;
    if (data == null) return [];

    Map<String, dynamic> root;
    if (data is Map<String, dynamic>) {
      root = data;
    } else {
      return [];
    }

    final body = root['response']?['body'];
    if (body == null) return [];

    final items = body['items']?['item'];
    if (items == null) return [];

    if (items is List) {
      return items
          .whereType<Map<String, dynamic>>()
          .map((e) => fromJson(e))
          .toList();
    } else if (items is Map<String, dynamic>) {
      return [fromJson(items)];
    }

    return [];
  }
}
