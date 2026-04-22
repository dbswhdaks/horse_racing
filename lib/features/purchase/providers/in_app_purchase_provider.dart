import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/iap_constants.dart';

class InAppPurchaseState {
  const InAppPurchaseState({
    this.isAvailable = false,
    this.isLoading = false,
    this.isPurchasePending = false,
    this.products = const [],
    this.notFoundProductIds = const [],
    this.purchasedProductIds = const {},
    this.isRestoring = false,
    this.errorMessage,
  });

  final bool isAvailable;
  final bool isLoading;
  final bool isPurchasePending;
  final List<ProductDetails> products;
  final List<String> notFoundProductIds;
  final Set<String> purchasedProductIds;
  final bool isRestoring;
  final String? errorMessage;

  InAppPurchaseState copyWith({
    bool? isAvailable,
    bool? isLoading,
    bool? isPurchasePending,
    List<ProductDetails>? products,
    List<String>? notFoundProductIds,
    Set<String>? purchasedProductIds,
    bool? isRestoring,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return InAppPurchaseState(
      isAvailable: isAvailable ?? this.isAvailable,
      isLoading: isLoading ?? this.isLoading,
      isPurchasePending: isPurchasePending ?? this.isPurchasePending,
      products: products ?? this.products,
      notFoundProductIds: notFoundProductIds ?? this.notFoundProductIds,
      purchasedProductIds: purchasedProductIds ?? this.purchasedProductIds,
      isRestoring: isRestoring ?? this.isRestoring,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

class _PurchaseVerificationResult {
  const _PurchaseVerificationResult({
    required this.isValid,
    required this.isActive,
    this.expiresAtUtc,
    this.message,
  });

  final bool isValid;
  final bool isActive;
  final DateTime? expiresAtUtc;
  final String? message;

  bool get isEntitledNow {
    final expiresAtUtc = this.expiresAtUtc;
    if (!isValid || !isActive) return false;
    if (expiresAtUtc == null) return true;
    return expiresAtUtc.isAfter(DateTime.now().toUtc());
  }
}

class InAppPurchaseNotifier extends StateNotifier<InAppPurchaseState> {
  InAppPurchaseNotifier({InAppPurchase? inAppPurchase})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance,
      super(const InAppPurchaseState());

  final InAppPurchase _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Timer? _entitlementRefreshTimer;

  static const _entitlementRefreshInterval = Duration(minutes: 5);

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[IAP] $message');
    }
  }

  Future<void> initialize() async {
    _log('initialize() start');
    state = state.copyWith(isLoading: true, clearErrorMessage: true);

    final available = await _inAppPurchase.isAvailable();
    _log('store available: $available');
    if (!available) {
      state = state.copyWith(
        isAvailable: false,
        isLoading: false,
        errorMessage: '스토어를 사용할 수 없습니다.',
      );
      return;
    }

    _purchaseSubscription ??= _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (error) {
        state = state.copyWith(
          isPurchasePending: false,
          errorMessage: '결제 스트림 오류: $error',
        );
      },
    );

    state = state.copyWith(isAvailable: true, isLoading: false);
    _log('initialize() success, refreshing products');
    await refreshProducts();
    await restorePurchases(clearExisting: true);
    _startEntitlementRefreshTimer();
  }

  Future<void> refreshProducts() async {
    _log('refreshProducts() start');
    if (!state.isAvailable) return;

    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    final response = await _inAppPurchase.queryProductDetails(
      IapConstants.productIds,
    );

    if (response.error != null) {
      _log('queryProductDetails error: ${response.error!.message}');
      state = state.copyWith(
        isLoading: false,
        errorMessage: response.error!.message,
      );
      return;
    }

    _log(
      'queryProductDetails success: found=${response.productDetails.length}, notFound=${response.notFoundIDs.length}',
    );
    if (response.notFoundIDs.isNotEmpty) {
      _log('notFoundIDs: ${response.notFoundIDs.join(', ')}');
    }

    state = state.copyWith(
      isLoading: false,
      products: response.productDetails,
      notFoundProductIds: response.notFoundIDs,
    );
  }

  Future<void> restorePurchases({bool clearExisting = false}) async {
    if (!state.isAvailable) return;
    state = state.copyWith(isRestoring: true, clearErrorMessage: true);
    if (clearExisting) {
      state = state.copyWith(purchasedProductIds: const {});
    }
    try {
      await _inAppPurchase.restorePurchases();
    } catch (error) {
      state = state.copyWith(
        errorMessage: '구매 복원 중 오류가 발생했습니다: $error',
      );
    } finally {
      state = state.copyWith(isRestoring: false);
    }
  }

  Future<bool> buyNonConsumable(String productId) async {
    _log('buyNonConsumable() requested: $productId');
    final product = _findProduct(productId);
    if (product == null) {
      _log('buyNonConsumable() failed - product not found: $productId');
      state = state.copyWith(errorMessage: '상품 정보를 찾을 수 없습니다: $productId');
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    _log('buyNonConsumable() launching billing flow: $productId');
    return _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<bool> startSubscriptionPurchase({
    String preferredProductId = 'premium_monthly',
  }) async {
    _log('startSubscriptionPurchase() requested: $preferredProductId');

    if (!state.isAvailable) {
      _log('store unavailable before purchase, re-initialize');
      await initialize();
    }

    if (state.products.isEmpty) {
      _log('products empty before purchase, refreshing');
      await refreshProducts();
    }

    final candidateIds = <String>[
      preferredProductId,
      'premium_monthly',
      'premium_yearly',
    ];

    ProductDetails? targetProduct;
    for (final id in candidateIds) {
      final found = _findProduct(id);
      if (found != null) {
        targetProduct = found;
        break;
      }
    }

    if (targetProduct == null) {
      final requested = candidateIds.join(', ');
      _log('startSubscriptionPurchase() failed - no product found: $requested');
      final availableProductIds = state.products.map((p) => p.id).join(', ');
      final notFoundProductIds = state.notFoundProductIds.join(', ');
      state = state.copyWith(
        errorMessage:
            '구독 상품 정보를 찾을 수 없습니다.\n'
            '요청 ID: $requested\n'
            '스토어 응답(found): ${availableProductIds.isEmpty ? '없음' : availableProductIds}\n'
            '스토어 응답(notFound): ${notFoundProductIds.isEmpty ? '없음' : notFoundProductIds}',
      );
      return false;
    }

    final launched = await buyNonConsumable(targetProduct.id);
    if (launched) return true;

    _log(
      'buyNonConsumable returned false, trying restore for already-owned subscription',
    );
    await restorePurchases();
    final hasSubscription = state.purchasedProductIds.any(
      IapConstants.subscriptionProductIds.contains,
    );
    if (hasSubscription) {
      state = state.copyWith(
        isPurchasePending: false,
        clearErrorMessage: true,
      );
      return true;
    }

    state = state.copyWith(
      errorMessage: state.errorMessage ?? '구매를 시작하지 못했습니다. 잠시 후 다시 시도해 주세요.',
    );
    return false;
  }

  Future<bool> buyConsumable(String productId) async {
    _log('buyConsumable() requested: $productId');
    final product = _findProduct(productId);
    if (product == null) {
      _log('buyConsumable() failed - product not found: $productId');
      state = state.copyWith(errorMessage: '상품 정보를 찾을 수 없습니다: $productId');
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    _log('buyConsumable() launching billing flow: $productId');
    return _inAppPurchase.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: true,
    );
  }

  ProductDetails? _findProduct(String productId) {
    for (final product in state.products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    _log('purchaseStream update received: ${purchases.length} item(s)');
    for (final purchase in purchases) {
      _log(
        'purchase status: ${purchase.status.name}, productId=${purchase.productID}',
      );
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _log('purchase pending: ${purchase.productID}');
          state = state.copyWith(
            isPurchasePending: true,
            clearErrorMessage: true,
          );
          break;

        case PurchaseStatus.error:
          _log(
            'purchase error: ${purchase.productID}, message=${purchase.error?.message}',
          );
          state = state.copyWith(
            isPurchasePending: false,
            errorMessage: purchase.error?.message ?? '결제 중 오류가 발생했습니다.',
          );
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _log('purchase needs verification: ${purchase.productID}');
          final verification = await _verifyPurchase(purchase);
          if (verification.isEntitledNow) {
            _log('purchase verified: ${purchase.productID}');
            _deliverProduct(purchase);
          } else {
            _log('purchase verification failed: ${purchase.productID}');
            _revokeProduct(purchase.productID);
            state = state.copyWith(
              errorMessage: verification.message ?? '결제 검증에 실패했습니다.',
              isPurchasePending: false,
            );
          }

          if (purchase.pendingCompletePurchase) {
            _log('completing purchase: ${purchase.productID}');
            await _inAppPurchase.completePurchase(purchase);
          }
          break;

        case PurchaseStatus.canceled:
          _log('purchase canceled: ${purchase.productID}');
          state = state.copyWith(
            isPurchasePending: false,
            errorMessage: '결제가 취소되었습니다.',
          );
          break;
      }
    }
  }

  Future<_PurchaseVerificationResult> _verifyPurchase(
    PurchaseDetails purchase,
  ) async {
    final verificationData =
        purchase.verificationData.serverVerificationData;
    final hasVerificationData = verificationData.isNotEmpty;
    if (!hasVerificationData) {
      return const _PurchaseVerificationResult(
        isValid: false,
        isActive: false,
        message: '영수증 데이터가 비어 있습니다.',
      );
    }

    final functionName = IapConstants.serverVerifyFunctionName.trim();
    if (functionName.isEmpty) {
      _log('server verify function not configured, fallback to local check');
      return const _PurchaseVerificationResult(
        isValid: true,
        isActive: true,
        message: '로컬 검증으로 처리되었습니다. 운영에서는 서버 검증을 활성화하세요.',
      );
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        functionName,
        body: {
          'platform': defaultTargetPlatform.name,
          'source': purchase.verificationData.source,
          'productId': purchase.productID,
          'verificationData': verificationData,
          'localVerificationData':
              purchase.verificationData.localVerificationData,
          'transactionDate': purchase.transactionDate,
          'purchaseId': purchase.purchaseID,
          'status': purchase.status.name,
        },
      );
      final payload = _asStringKeyedMap(response.data);
      final isValid = _readBool(
        payload,
        const ['isValid', 'valid', 'ok'],
        defaultValue: false,
      );
      final activeByPayload = _readBool(
        payload,
        const ['isActive', 'active', 'entitled'],
        defaultValue: isValid,
      );
      final expiresAtUtc = _parseDateTimeUtc(
        payload['expiresAt'] ?? payload['expires_at'] ?? payload['expiryTime'],
      );
      final isActiveByTime =
          expiresAtUtc == null || expiresAtUtc.isAfter(DateTime.now().toUtc());
      final message =
          payload['message']?.toString() ?? payload['reason']?.toString();

      _log(
        'verifyPurchase(server): productId=${purchase.productID}, isValid=$isValid, active=$activeByPayload, expiresAt=$expiresAtUtc',
      );
      return _PurchaseVerificationResult(
        isValid: isValid,
        isActive: activeByPayload && isActiveByTime,
        expiresAtUtc: expiresAtUtc,
        message: message,
      );
    } catch (error) {
      _log('verifyPurchase(server) error: $error');
      return _PurchaseVerificationResult(
        isValid: false,
        isActive: false,
        message: '서버 검증 중 오류가 발생했습니다: $error',
      );
    }
  }

  Map<String, dynamic> _asStringKeyedMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  bool _readBool(
    Map<String, dynamic> payload,
    List<String> keys, {
    required bool defaultValue,
  }) {
    for (final key in keys) {
      final value = payload[key];
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
      if (value is num) {
        return value != 0;
      }
    }
    return defaultValue;
  }

  DateTime? _parseDateTimeUtc(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    return parsed?.toUtc();
  }

  void _startEntitlementRefreshTimer() {
    _entitlementRefreshTimer?.cancel();
    _entitlementRefreshTimer = Timer.periodic(
      _entitlementRefreshInterval,
      (_) async {
        if (!state.isAvailable || state.isPurchasePending) return;
        _log('periodic entitlement refresh start');
        await restorePurchases(clearExisting: true);
      },
    );
  }

  void _revokeProduct(String productId) {
    final updated = {...state.purchasedProductIds}..remove(productId);
    state = state.copyWith(purchasedProductIds: updated);
  }

  bool _isPremiumProductId(String productId) {
    return IapConstants.subscriptionProductIds.contains(productId);
  }

  void _deliverProduct(PurchaseDetails purchase) {
    if (!_isPremiumProductId(purchase.productID)) {
      _log('skip deliver - unknown productId: ${purchase.productID}');
      return;
    }
    final purchased = {...state.purchasedProductIds, purchase.productID};
    _log('deliverProduct: ${purchase.productID}');
    state = state.copyWith(
      purchasedProductIds: purchased,
      isPurchasePending: false,
      clearErrorMessage: true,
    );
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _entitlementRefreshTimer?.cancel();
    super.dispose();
  }
}

final inAppPurchaseProvider =
    StateNotifierProvider<InAppPurchaseNotifier, InAppPurchaseState>((ref) {
      final notifier = InAppPurchaseNotifier();
      unawaited(notifier.initialize());
      return notifier;
    });
