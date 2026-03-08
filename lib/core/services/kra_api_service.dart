import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

    final response = await _get(ApiConstants.racePlanPath, params);
    if (response == null) return [];

    var races = _parseList(response, (json) => Race.fromJson(json));

    if (races.isEmpty && rcDate != null && rcDate.length == 8 && rcMonth == null) {
      final monthParam = rcDate.substring(0, 6);
      final monthResponse = await _get(
        ApiConstants.racePlanPath,
        {'meet': meet, 'rc_month': monthParam},
      );
      if (monthResponse != null) {
        races = _parseList(monthResponse, (json) => Race.fromJson(json));
        races = races.where((r) => r.raceDate == rcDate).toList();
      }
    }

    return races;
  }

  Future<List<RaceEntry>> getRaceStartList({
    required String meet,
    String? rcDate,
    int? rcNo,
  }) async {
    final params = <String, dynamic>{
      'meet': meet,
      'pageNo': 1,
      'numOfRows': 500,
    };

    if (rcDate != null && rcDate.length == 8) {
      params['rc_date'] = rcDate;
    }
    if (rcNo != null) params['rc_no'] = rcNo;

    final response = await _get(ApiConstants.raceStartListPath, params);
    if (response == null) return [];

    // 첫 아이템의 필드명과 주요 값을 디버그 로그로 출력
    final rawItems = response.data?['response']?['body']?['items']?['item'];
    if (rawItems is List && rawItems.isNotEmpty) {
      final first = rawItems.first;
      if (first is Map) {
        debugPrint('[KRA] 출전표 필드 목록: ${first.keys.toList()}');
        debugPrint('[KRA] chulNo=${first['chulNo']}, hrNo=${first['hrNo']}, '
            'hrNm=${first['hrNm']}, jkNm=${first['jkNm']}, '
            'jockyNm=${first['jockyNm']}, trNm=${first['trNm']}');
      }
    } else if (rawItems is Map) {
      debugPrint('[KRA] 출전표 필드 목록: ${rawItems.keys.toList()}');
    }

    var entries = _parseList(response, (json) => RaceEntry.fromJson(json));

    if (rcNo != null && entries.isNotEmpty) {
      final filtered = entries.where((e) => e.raceNo == rcNo).toList();
      if (filtered.isNotEmpty) return filtered;
    }
    return entries;
  }

  Future<List<RaceResult>> getRaceResult({
    required String meet,
    String? rcDate,
    int? rcNo,
  }) async {
    final params = <String, dynamic>{
      'rccrs_cd': meet,
      'pageNo': 1,
      'numOfRows': 500,
    };
    if (rcDate != null && rcDate.length == 8) {
      params['race_dt'] = rcDate;
    }
    if (rcNo != null) params['race_no'] = rcNo;

    final response = await _get(ApiConstants.raceResultPath, params);
    if (response == null) return [];
    var results = _parseList(response, (json) => RaceResult.fromJson(json));

    // API155는 race_no 서버 필터가 안 되므로 클라이언트에서 필터링
    if (rcNo != null && results.isNotEmpty) {
      final filtered = results.where((r) => r.raceNo == rcNo).toList();
      if (filtered.isNotEmpty) return filtered;
    }
    return results;
  }

  Future<List<Odds>> getOddInfo({
    required String meet,
    String? rcDate,
    int? rcNo,
  }) async {
    final params = <String, dynamic>{
      'meet': meet,
      'pageNo': 1,
      'numOfRows': 500,
    };
    if (rcDate != null && rcDate.length == 8) {
      params['rc_date'] = rcDate;
    }
    if (rcNo != null) params['rc_no'] = rcNo;

    final response = await _get(ApiConstants.oddInfoPath, params);
    if (response == null) return [];
    return _parseList(response, (json) => Odds.fromJson(json));
  }

  Future<Response?> _get(
    String path,
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await _dio.get(path, queryParameters: params);
      debugPrint('[KRA] $path → ${response.statusCode}');
      return response;
    } on DioException catch (e) {
      debugPrint('[KRA] $path 요청 실패: ${e.response?.statusCode} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[KRA] $path 오류: $e');
      return null;
    }
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
      debugPrint('[KRA] 응답이 JSON이 아닙니다: ${data.runtimeType}');
      return [];
    }

    final header = root['response']?['header'];
    final resultCode = header?['resultCode']?.toString();
    if (resultCode != null && resultCode != '00' && resultCode != '0000') {
      debugPrint('[KRA] API 오류: ${header?['resultMsg']} (code=$resultCode)');
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
