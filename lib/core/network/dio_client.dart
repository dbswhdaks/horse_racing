import 'package:dio/dio.dart';
import '../constants/api_constants.dart';

class DioClient {
  DioClient._();

  static final Dio kra =
      Dio(
          BaseOptions(
            baseUrl: ApiConstants.baseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 45),
            queryParameters: {
              'ServiceKey': ApiConstants.serviceKey,
              '_type': 'json',
            },
          ),
        )
        ..interceptors.add(
          LogInterceptor(
            requestBody: false,
            responseBody: true,
            logPrint: (o) {},
          ),
        );

  static final Dio ml = Dio(
    BaseOptions(
      baseUrl: ApiConstants.mlBackendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );
}
