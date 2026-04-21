import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/constants/iap_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/in_app_purchase_provider.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  static const String routePath = '/subscription';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iapState = ref.watch(inAppPurchaseProvider);
    final notifier = ref.read(inAppPurchaseProvider.notifier);
    final productsById = {for (final p in iapState.products) p.id: p};
    final plans = [
      _PlanUi(
        productId: 'premium_daily',
        title: '하루 이용권',
        subtitle: '하루 동안 프리미엄 기능을 이용할 수 있어요.',
        badge: '가볍게 시작',
      ),
      _PlanUi(
        productId: 'premium_monthly',
        title: '월간 구독',
        subtitle: '가장 많이 선택하는 플랜',
        badge: '인기',
      ),
      _PlanUi(
        productId: 'premium_yearly',
        title: '연간 구독',
        subtitle: '오래 사용할수록 더 합리적',
        badge: '최대 혜택',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('구독하기')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: notifier.refreshProducts,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  children: [
                    _HeroCard(
                      isLoading: iapState.isLoading,
                      isAvailable: iapState.isAvailable,
                      errorMessage: iapState.errorMessage,
                      onRetry: notifier.refreshProducts,
                    ),
                    const SizedBox(height: 16),
                    ...plans.map((plan) {
                      final product = productsById[plan.productId];
                      final purchased = iapState.purchasedProductIds.contains(
                        plan.productId,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PlanCard(
                          plan: plan,
                          product: product,
                          purchased: purchased,
                          loading: iapState.isPurchasePending,
                          onPressed: () async {
                            if (product == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '상품 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.',
                                  ),
                                ),
                              );
                              return;
                            }

                            final ok = await notifier.buyNonConsumable(
                              plan.productId,
                            );
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('결제를 시작하지 못했습니다.'),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: notifier.restorePurchases,
                      child: const Text('구매 복원'),
                    ),
                    const SizedBox(height: 8),
                    _InfoPanel(
                      enabled: iapState.isAvailable,
                      hasProducts: iapState.products.isNotEmpty,
                    ),
                  ],
                ),
              ),
            ),
            if (iapState.isPurchasePending)
              const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.isLoading,
    required this.isAvailable,
    required this.errorMessage,
    required this.onRetry,
  });

  final bool isLoading;
  final bool isAvailable;
  final String? errorMessage;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A3E64), Color(0xFF12233E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'PREMIUM',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '광고 없이 더 빠르게,\n프리미엄 분석을 이용하세요',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (isLoading)
            const Text('상품 정보를 불러오는 중...')
          else if (!isAvailable)
            Row(
              children: [
                const Expanded(child: Text('스토어에 연결할 수 없습니다.')),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('다시 시도'),
                ),
              ],
            )
          else if (errorMessage != null)
            Text(errorMessage!, style: TextStyle(color: Colors.red.shade200))
          else
            const Text('원하는 플랜을 선택해 즉시 구독을 시작할 수 있어요.'),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.product,
    required this.purchased,
    required this.loading,
    required this.onPressed,
  });

  final _PlanUi plan;
  final ProductDetails? product;
  final bool purchased;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: purchased ? AppTheme.accentGold : Colors.white12,
          width: purchased ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                plan.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  plan.badge,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  product?.price ?? '상품 확인 중',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton(
                onPressed: loading ? null : onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                ),
                child: Text(purchased ? '구독 중' : '구독하기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.enabled, required this.hasProducts});

  final bool enabled;
  final bool hasProducts;

  @override
  Widget build(BuildContext context) {
    final productText = IapConstants.productIds.join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        enabled && hasProducts
            ? '등록된 결제 플랜: $productText'
            : '결제 플랜을 불러오지 못하면 Play Console 상품 ID 설정을 확인하세요.\n$productText',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade400,
          height: 1.45,
        ),
      ),
    );
  }
}

class _PlanUi {
  const _PlanUi({
    required this.productId,
    required this.title,
    required this.subtitle,
    required this.badge,
  });

  final String productId;
  final String title;
  final String subtitle;
  final String badge;
}
