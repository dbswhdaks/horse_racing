import 'package:dio/dio.dart';
import '../constants/api_constants.dart';

class DioClient {
  DioClient._();

  static final Dio kra =
      Dio(
          BaseOptions(
            baseUrl: ApiConstants.baseUrl,
            // 웹에서는 응답 헤더를 받을 때까지가 connectTimeout 에 포함되는데,
            // KRA 는 첫 바이트까지 30초 넘게 걸리기도 한다.
            connectTimeout: const Duration(seconds: 45),
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
