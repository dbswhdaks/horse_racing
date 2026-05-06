class ProfileLockConstants {
  ProfileLockConstants._();

  /// 프로필 화면 잠금 해제 비밀번호.
  /// 빌드 시점에 외부 주입이 필요하면 --dart-define=PROFILE_PASSWORD=... 로 덮어쓸 수 있다.
  static const String profilePassword = String.fromEnvironment(
    'PROFILE_PASSWORD',
    defaultValue: '71108368',
  );

  /// SharedPreferences 에 프로필 잠금 해제 상태를 저장하는 키.
  static const String storageKey = 'profile_unlocked';
}
