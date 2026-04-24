import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/iap_constants.dart';

class SubscriptionEntitlement {
  const SubscriptionEntitlement({
    required this.productId,
    required this.expiresAtUtc,
    this.startedAtUtc,
    this.orderId,
  });

  final String productId;
  final DateTime? startedAtUtc;
  final DateTime expiresAtUtc;
  final String? orderId;
}

class InAppPurchaseState {
  const InAppPurchaseState({
    this.isAvailable = false,
    this.isLoading = false,
    this.isPurchasePending = false,
    this.products = const [],
    this.notFoundProductIds = const [],
    this.purchasedProductIds = const {},
    this.entitlementByProductId = const {},
    this.isRestoring = false,
    this.errorMessage,
  });

  final bool isAvailable;
  final bool isLoading;
  final bool isPurchasePending;
  final List<ProductDetails> products;
  final List<String> notFoundProductIds;
  final Set<String> purchasedProductIds;
  final Map<String, SubscriptionEntitlement> entitlementByProductId;
  final bool isRestoring;
  final String? errorMessage;

  InAppPurchaseState copyWith({
    bool? isAvailable,
    bool? isLoading,
    bool? isPurchasePending,
    List<ProductDetails>? products,
    List<String>? notFoundProductIds,
    Set<String>? purchasedProductIds,
    Map<String, SubscriptionEntitlement>? entitlementByProductId,
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
      entitlementByProductId:
          entitlementByProductId ?? this.entitlementByProductId,
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
  static const _entitlementExpiryKeyPrefix = 'iap_entitlement_expiry_';
  static const _entitlementStartKeyPrefix = 'iap_entitlement_start_';
  static const _entitlementOrderIdKeyPrefix = 'iap_entitlement_order_id_';

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[IAP] $message');
    }
  }

  Future<void> initialize() async {
    _log('initialize() start');
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    await _restoreEntitlementsFromLocalCache();

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
      state = state.copyWith(
        purchasedProductIds: const {},
        entitlementByProductId: const {},
      );
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
    if (_hasActiveSubscription()) {
      _log('active subscription already exists, skip repurchase flow');
      state = state.copyWith(isPurchasePending: false, clearErrorMessage: true);
      return true;
    }

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
            await _deliverProduct(
              purchase,
              verifiedExpiresAtUtc: verification.expiresAtUtc,
            );
          } else {
            _log('purchase verification failed: ${purchase.productID}');
            await _revokeProduct(purchase.productID);
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
      final expiresAtUtc = _calculateLocalSubscriptionExpiresAtUtc(
        productId: purchase.productID,
        transactionDate: purchase.transactionDate,
      );
      if (expiresAtUtc == null) {
        return _PurchaseVerificationResult(
          isValid: false,
          isActive: false,
          message: '구독 만료일 계산에 실패했습니다. 상품 정보를 확인해 주세요.',
        );
      }
      final isActive = expiresAtUtc.isAfter(DateTime.now().toUtc());
      return _PurchaseVerificationResult(
        isValid: true,
        isActive: isActive,
        expiresAtUtc: expiresAtUtc,
        message: isActive
            ? '로컬 검증으로 처리되었습니다.'
            : '구독 기간이 만료되었습니다. 다시 구독해 주세요.',
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
      if (!isValid) {
        return _PurchaseVerificationResult(
          isValid: false,
          isActive: false,
          message: payload['message']?.toString() ?? '서버 검증에 실패했습니다.',
        );
      }
      if (expiresAtUtc == null) {
        return const _PurchaseVerificationResult(
          isValid: false,
          isActive: false,
          message:
              '서버 검증 응답에 구독 만료일(expiresAt)이 없습니다. 서버 설정을 확인해 주세요.',
        );
      }
      final isActiveByTime =
          expiresAtUtc.isAfter(DateTime.now().toUtc());
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

  DateTime? _calculateLocalSubscriptionExpiresAtUtc({
    required String productId,
    required String? transactionDate,
  }) {
    final purchasedAtUtc = _parsePurchaseDateUtc(transactionDate);
    if (purchasedAtUtc == null) return null;

    switch (productId) {
      case 'premium_monthly':
        return _addMonthsUtc(purchasedAtUtc, 1);
      case 'premium_yearly':
        return _addMonthsUtc(purchasedAtUtc, 12);
      default:
        return null;
    }
  }

  DateTime? _parsePurchaseDateUtc(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;

    final epoch = int.tryParse(text);
    if (epoch != null) {
      final isSeconds = text.length <= 10;
      return DateTime.fromMillisecondsSinceEpoch(
        isSeconds ? epoch * 1000 : epoch,
        isUtc: true,
      );
    }

    final parsed = DateTime.tryParse(text);
    return parsed?.toUtc();
  }

  DateTime _addMonthsUtc(DateTime baseUtc, int months) {
    final totalMonths = (baseUtc.month - 1) + months;
    final year = baseUtc.year + (totalMonths ~/ 12);
    final month = (totalMonths % 12) + 1;
    final lastDayOfMonth = DateTime.utc(year, month + 1, 0).day;
    final day = baseUtc.day > lastDayOfMonth ? lastDayOfMonth : baseUtc.day;

    return DateTime.utc(
      year,
      month,
      day,
      baseUtc.hour,
      baseUtc.minute,
      baseUtc.second,
      baseUtc.millisecond,
      baseUtc.microsecond,
    );
  }

  DateTime _subtractMonthsUtc(DateTime baseUtc, int months) {
    return _addMonthsUtc(baseUtc, -months);
  }

  DateTime? _deriveSubscriptionStartUtc({
    required String productId,
    required DateTime expiresAtUtc,
  }) {
    switch (productId) {
      case 'premium_monthly':
        return _subtractMonthsUtc(expiresAtUtc, 1);
      case 'premium_yearly':
        return _subtractMonthsUtc(expiresAtUtc, 12);
      default:
        return null;
    }
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

  Future<void> _revokeProduct(String productId) async {
    final updated = {...state.purchasedProductIds}..remove(productId);
    await _clearCachedEntitlement(productId);
    final updatedEntitlements = {...state.entitlementByProductId}
      ..remove(productId);
    state = state.copyWith(
      purchasedProductIds: updated,
      entitlementByProductId: updatedEntitlements,
    );
  }

  bool _isPremiumProductId(String productId) {
    return IapConstants.subscriptionProductIds.contains(productId);
  }

  bool _hasActiveSubscription() {
    return state.purchasedProductIds.any(
      IapConstants.subscriptionProductIds.contains,
    );
  }

  Future<void> _deliverProduct(
    PurchaseDetails purchase, {
    DateTime? verifiedExpiresAtUtc,
  }) async {
    if (!_isPremiumProductId(purchase.productID)) {
      _log('skip deliver - unknown productId: ${purchase.productID}');
      return;
    }
    final expiresAtUtc = _resolveEntitlementExpiryUtc(
      purchase: purchase,
      verifiedExpiresAtUtc: verifiedExpiresAtUtc,
    );
    if (expiresAtUtc == null) {
      _log('skip cache - no entitlement expiry: ${purchase.productID}');
    } else {
      final startedAtUtc =
          _parsePurchaseDateUtc(purchase.transactionDate) ??
          _deriveSubscriptionStartUtc(
            productId: purchase.productID,
            expiresAtUtc: expiresAtUtc,
          );
      final orderId = purchase.purchaseID?.trim();
      await _cacheEntitlement(
        productId: purchase.productID,
        expiresAtUtc: expiresAtUtc,
        startedAtUtc: startedAtUtc,
        orderId: (orderId == null || orderId.isEmpty) ? null : orderId,
      );
      final updatedEntitlements = {...state.entitlementByProductId}
        ..[purchase.productID] = SubscriptionEntitlement(
          productId: purchase.productID,
          startedAtUtc: startedAtUtc,
          expiresAtUtc: expiresAtUtc,
          orderId: (orderId == null || orderId.isEmpty) ? null : orderId,
        );
      state = state.copyWith(entitlementByProductId: updatedEntitlements);
    }
    final purchased = {...state.purchasedProductIds, purchase.productID};
    _log('deliverProduct: ${purchase.productID}');
    state = state.copyWith(
      purchasedProductIds: purchased,
      isPurchasePending: false,
      clearErrorMessage: true,
    );
  }

  DateTime? _resolveEntitlementExpiryUtc({
    required PurchaseDetails purchase,
    required DateTime? verifiedExpiresAtUtc,
  }) {
    if (verifiedExpiresAtUtc != null) return verifiedExpiresAtUtc.toUtc();
    return _calculateLocalSubscriptionExpiresAtUtc(
      productId: purchase.productID,
      transactionDate: purchase.transactionDate,
    );
  }

  Future<void> _restoreEntitlementsFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nowUtc = DateTime.now().toUtc();
      final active = <String>{};
      final activeEntitlements = <String, SubscriptionEntitlement>{};

      for (final productId in IapConstants.subscriptionProductIds) {
        final expiryKey = '$_entitlementExpiryKeyPrefix$productId';
        final startKey = '$_entitlementStartKeyPrefix$productId';
        final orderIdKey = '$_entitlementOrderIdKeyPrefix$productId';
        final rawExpiry = prefs.getString(expiryKey);
        if (rawExpiry == null || rawExpiry.isEmpty) continue;
        final expiresAtUtc = DateTime.tryParse(rawExpiry)?.toUtc();
        if (expiresAtUtc == null) {
          await prefs.remove(expiryKey);
          await prefs.remove(startKey);
          await prefs.remove(orderIdKey);
          continue;
        }
        if (expiresAtUtc.isAfter(nowUtc)) {
          active.add(productId);
          final rawStart = prefs.getString(startKey);
          final rawOrderId = prefs.getString(orderIdKey);
          final startedAtUtc =
              DateTime.tryParse(rawStart ?? '')?.toUtc() ??
              _deriveSubscriptionStartUtc(
                productId: productId,
                expiresAtUtc: expiresAtUtc,
              );
          activeEntitlements[productId] = SubscriptionEntitlement(
            productId: productId,
            startedAtUtc: startedAtUtc,
            expiresAtUtc: expiresAtUtc,
            orderId: rawOrderId == null || rawOrderId.isEmpty
                ? null
                : rawOrderId,
          );
        } else {
          await prefs.remove(expiryKey);
          await prefs.remove(startKey);
          await prefs.remove(orderIdKey);
        }
      }

      if (active.isNotEmpty) {
        _log('restored local entitlement: ${active.join(', ')}');
        state = state.copyWith(
          purchasedProductIds: active,
          entitlementByProductId: activeEntitlements,
        );
      }
    } catch (error) {
      _log('restore local entitlement failed: $error');
    }
  }

  Future<void> _cacheEntitlement(
    {
    required String productId,
    required DateTime expiresAtUtc,
    required DateTime? startedAtUtc,
    required String? orderId,
  }
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryKey = '$_entitlementExpiryKeyPrefix$productId';
      final startKey = '$_entitlementStartKeyPrefix$productId';
      final orderIdKey = '$_entitlementOrderIdKeyPrefix$productId';
      await prefs.setString(expiryKey, expiresAtUtc.toUtc().toIso8601String());
      if (startedAtUtc != null) {
        await prefs.setString(startKey, startedAtUtc.toUtc().toIso8601String());
      } else {
        await prefs.remove(startKey);
      }
      if (orderId != null && orderId.isNotEmpty) {
        await prefs.setString(orderIdKey, orderId);
      } else {
        await prefs.remove(orderIdKey);
      }
    } catch (error) {
      _log('cache entitlement failed: $error');
    }
  }

  Future<void> _clearCachedEntitlement(String productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryKey = '$_entitlementExpiryKeyPrefix$productId';
      final startKey = '$_entitlementStartKeyPrefix$productId';
      final orderIdKey = '$_entitlementOrderIdKeyPrefix$productId';
      await prefs.remove(expiryKey);
      await prefs.remove(startKey);
      await prefs.remove(orderIdKey);
    } catch (error) {
      _log('clear cached entitlement failed: $error');
    }
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
