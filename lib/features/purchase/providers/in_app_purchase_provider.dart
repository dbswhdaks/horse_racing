import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/constants/iap_constants.dart';

class InAppPurchaseState {
  const InAppPurchaseState({
    this.isAvailable = false,
    this.isLoading = false,
    this.isPurchasePending = false,
    this.products = const [],
    this.purchasedProductIds = const {},
    this.errorMessage,
  });

  final bool isAvailable;
  final bool isLoading;
  final bool isPurchasePending;
  final List<ProductDetails> products;
  final Set<String> purchasedProductIds;
  final String? errorMessage;

  InAppPurchaseState copyWith({
    bool? isAvailable,
    bool? isLoading,
    bool? isPurchasePending,
    List<ProductDetails>? products,
    Set<String>? purchasedProductIds,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return InAppPurchaseState(
      isAvailable: isAvailable ?? this.isAvailable,
      isLoading: isLoading ?? this.isLoading,
      isPurchasePending: isPurchasePending ?? this.isPurchasePending,
      products: products ?? this.products,
      purchasedProductIds: purchasedProductIds ?? this.purchasedProductIds,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

class InAppPurchaseNotifier extends StateNotifier<InAppPurchaseState> {
  InAppPurchaseNotifier({InAppPurchase? inAppPurchase})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance,
      super(const InAppPurchaseState());

  final InAppPurchase _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);

    final available = await _inAppPurchase.isAvailable();
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
    await refreshProducts();
  }

  Future<void> refreshProducts() async {
    if (!state.isAvailable) return;

    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    final response = await _inAppPurchase.queryProductDetails(
      IapConstants.productIds,
    );

    if (response.error != null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: response.error!.message,
      );
      return;
    }

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('IAP not found product IDs: ${response.notFoundIDs}');
    }

    state = state.copyWith(isLoading: false, products: response.productDetails);
  }

  Future<void> restorePurchases() async {
    if (!state.isAvailable) return;
    await _inAppPurchase.restorePurchases();
  }

  Future<bool> buyNonConsumable(String productId) async {
    final product = _findProduct(productId);
    if (product == null) {
      state = state.copyWith(errorMessage: '상품 정보를 찾을 수 없습니다: $productId');
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    return _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<bool> buyConsumable(String productId) async {
    final product = _findProduct(productId);
    if (product == null) {
      state = state.copyWith(errorMessage: '상품 정보를 찾을 수 없습니다: $productId');
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
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
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(
            isPurchasePending: true,
            clearErrorMessage: true,
          );
          break;

        case PurchaseStatus.error:
          state = state.copyWith(
            isPurchasePending: false,
            errorMessage: purchase.error?.message ?? '결제 중 오류가 발생했습니다.',
          );
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final isValid = await _verifyPurchase(purchase);
          if (isValid) {
            _deliverProduct(purchase);
          } else {
            state = state.copyWith(
              errorMessage: '결제 검증에 실패했습니다.',
              isPurchasePending: false,
            );
          }

          if (purchase.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchase);
          }
          break;

        case PurchaseStatus.canceled:
          state = state.copyWith(
            isPurchasePending: false,
            errorMessage: '결제가 취소되었습니다.',
          );
          break;
      }
    }
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    // 운영 시에는 서버에서 영수증 검증을 수행한 뒤 true/false를 반환하세요.
    return purchase.verificationData.serverVerificationData.isNotEmpty;
  }

  void _deliverProduct(PurchaseDetails purchase) {
    final purchased = {...state.purchasedProductIds, purchase.productID};
    state = state.copyWith(
      purchasedProductIds: purchased,
      isPurchasePending: false,
      clearErrorMessage: true,
    );
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}

final inAppPurchaseProvider =
    StateNotifierProvider<InAppPurchaseNotifier, InAppPurchaseState>((ref) {
      final notifier = InAppPurchaseNotifier();
      unawaited(notifier.initialize());
      return notifier;
    });
