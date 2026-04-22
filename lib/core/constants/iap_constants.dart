class IapConstants {
  IapConstants._();

  // Play Console에 등록한 인앱 상품 ID와 동일해야 합니다.
  static const Set<String> productIds = {
    'premium_monthly',
    'premium_yearly',
  };

  static const Set<String> subscriptionProductIds = {
    'premium_monthly',
    'premium_yearly',
  };

  // 운영에서 서버 영수증 검증을 사용한다면 --dart-define으로 함수명을 주입하세요.
  // 예: --dart-define=IAP_VERIFY_FUNCTION=verify_android_subscription
  static const String serverVerifyFunctionName = String.fromEnvironment(
    'IAP_VERIFY_FUNCTION',
    defaultValue: '',
  );
}
