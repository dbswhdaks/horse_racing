import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../../models/prediction.dart';

class MlApiService {
  final Dio _dio = DioClient.ml;

  Future<PredictionReport?> getPrediction({
    required String meet,
    required String date,
    required int raceNo,
  }) async {
    try {
      final response = await _dio.get(
        '/predict/$meet/$date/$raceNo',
      );
      if (response.data != null) {
        return PredictionReport.fromJson(response.data);
      }
    } on DioException {
      return null;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getRecommendations({
    String? trackCondition,
    String? weather,
    int? distance,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (trackCondition != null) params['track_condition'] = trackCondition;
      if (weather != null) params['weather'] = weather;
      if (distance != null) params['distance'] = distance;

      final response = await _dio.get(
        '/recommendations',
        queryParameters: params,
      );
      if (response.data is List) {
        return (response.data as List).cast<Map<String, dynamic>>();
      }
    } on DioException {
      return [];
    }
    return [];
  }
}
