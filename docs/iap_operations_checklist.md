# IAP 운영 점검 체크리스트

이 문서는 Android 구독 결제(`premium_monthly`, `premium_yearly`) 운영 전 점검 절차입니다.

## 1) 상품 ID 최종 점검

- Play Console에 아래 상품이 `활성` 상태인지 확인
  - `premium_monthly`
  - `premium_yearly`
- 앱 코드 상품 ID와 콘솔 상품 ID가 완전히 일치하는지 확인
- `premium_daily`는 코드/콘솔에서 사용하지 않도록 정리

## 2) 서버 영수증 검증 적용 여부 확인

### Edge Function 배포

1. 함수 배포
   - `supabase/functions/verify_android_subscription/index.ts`
2. 환경 변수 설정
   - `ANDROID_PACKAGE_NAME`: 예) `com.horseracingplus.app`
   - `GOOGLE_SERVICE_ACCOUNT_EMAIL`: Play Developer API 권한이 있는 서비스 계정 이메일
   - `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY`: 서비스 계정 private key (줄바꿈은 `\n` 유지 가능)
3. 앱 실행 시 검증 함수명 주입
   - `--dart-define=IAP_VERIFY_FUNCTION=verify_android_subscription`

### 검증 API 정상 여부

- 함수가 아래 필드를 반환하는지 확인
  - `isValid` (bool)
  - `isActive` (bool)
  - `expiresAt` (ISO8601 string or null)
- 검증 실패 시 앱에서 entitlement가 해제되는지 확인

## 3) 구매 복원 점검 (재설치/기기 변경)

### 재설치 시나리오

1. 구독 구매 완료
2. 앱 삭제 후 재설치
3. 동일 Google 계정으로 로그인
4. 앱 시작 후 잠금이 자동 해제되는지 확인

### 기기 변경 시나리오

1. 기존 기기에서 구독 상태 확인
2. 신규 기기에 앱 설치
3. 동일 Google 계정으로 로그인
4. 앱 시작 후 잠금이 자동 해제되는지 확인

## 4) 구독 만료/취소 후 접근 제한 재적용 점검

1. Play Console 또는 테스트 계정에서 구독 취소 처리
2. 만료/취소 반영 시간을 지난 뒤 앱 실행
3. 자동 동기화 또는 앱 재실행 후 잠금이 다시 걸리는지 확인
4. 잠금 화면에서 결제 재시도 시 정상 복구되는지 확인

## 5) 내부 테스트 트랙 점검 (테스트 계정 외)

1. 앱을 내부 테스트 트랙 빌드로 설치
2. 라이선스 테스트 계정이 아닌 내부 테스트 사용자 계정으로 로그인
3. 아래 시나리오 각각 확인
   - 구매 성공
   - 구매 취소
   - 구매 복원
   - 만료/취소 후 잠금 재적용
4. 앱 로그에서 확인 포인트
   - `[IAP] purchase status`
   - `[IAP] verifyPurchase(server)`
   - `[IAP] deliverProduct`

## 6) 장애 시 우선 점검

- `IAP_VERIFY_FUNCTION` 누락 여부
- Edge Function 환경 변수 누락 여부
- 서비스 계정에 Android Publisher API 권한이 있는지
- 앱 패키지명(`applicationId`)과 `ANDROID_PACKAGE_NAME` 일치 여부
