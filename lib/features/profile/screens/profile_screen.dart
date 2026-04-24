import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/iap_constants.dart';
import '../../purchase/providers/in_app_purchase_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iapState = ref.watch(inAppPurchaseProvider);
    final activeSubscriptionIds = iapState.purchasedProductIds
        .where(IapConstants.subscriptionProductIds.contains)
        .toSet();
    final activeEntitlements = iapState.entitlementByProductId.values
        .where((entitlement) => activeSubscriptionIds.contains(entitlement.productId))
        .toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    final hasSubscription = activeSubscriptionIds.isNotEmpty;
    DateTime? nearestExpiresAtUtc;
    for (final entitlement in activeEntitlements) {
      final expiry = entitlement.expiresAtUtc;
      if (nearestExpiresAtUtc == null || expiry.isBefore(nearestExpiresAtUtc)) {
        nearestExpiresAtUtc = expiry;
      }
    }
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm');

    String planLabel(String productId) {
      switch (productId) {
        case 'premium_monthly':
          return '프리미엄 월간';
        case 'premium_yearly':
          return '프리미엄 연간';
        default:
          return productId;
      }
    }

    String formatDate(DateTime? dateTime) {
      if (dateTime == null) return '확인 불가';
      return dateFormat.format(dateTime.toLocal());
    }

    SubscriptionEntitlement? findEntitlement(String productId) {
      for (final entitlement in activeEntitlements) {
        if (entitlement.productId == productId) return entitlement;
      }
      return null;
    }

    String remainingDaysLabel(DateTime? expiresAtUtc) {
      if (expiresAtUtc == null) return '-';
      final nowUtc = DateTime.now().toUtc();
      final diff = expiresAtUtc.difference(nowUtc);
      if (diff.isNegative) return '만료';
      final remainDays = (diff.inHours / 24).ceil();
      if (remainDays <= 0) return 'D-Day';
      return 'D-$remainDays';
    }

    Future<void> copyOrderId(String? orderId) async {
      final value = orderId?.trim() ?? '';
      if (value.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('복사할 주문 아이디가 없습니다.')));
        }
        return;
      }
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('주문 아이디를 복사했습니다.')));
      }
    }

    Future<void> openSubscriptionManagement() async {
      final uri = Uri.parse('https://play.google.com/store/account/subscriptions');
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('구독 관리 페이지를 열 수 없습니다.')));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('프로필')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                color: Colors.white.withValues(alpha: 0.03),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '구독 상태',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        hasSubscription
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: hasSubscription
                            ? Colors.greenAccent.shade100
                            : Colors.orangeAccent.shade100,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasSubscription ? '구독 활성' : '구독 비활성',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: hasSubscription
                              ? Colors.greenAccent.shade100
                              : Colors.orangeAccent.shade100,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (hasSubscription)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '이용 중 플랜: ${activeSubscriptionIds.map(planLabel).join(', ')}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade300),
                        ),
                        const SizedBox(height: 10),
                        ...activeSubscriptionIds.map((productId) {
                          final entitlement = findEntitlement(productId);
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white.withValues(alpha: 0.04),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '주문 아이디: ${entitlement?.orderId ?? '확인 불가'}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          copyOrderId(entitlement?.orderId),
                                      icon: const Icon(Icons.copy_rounded, size: 18),
                                      tooltip: '주문 아이디 복사',
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '구독 시작일: ${formatDate(entitlement?.startedAtUtc)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '구독 종료일: ${formatDate(entitlement?.expiresAtUtc)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    )
                  else
                    Text(
                      '아직 활성화된 구독이 없습니다. 구독 결제 화면에서 플랜을 선택해 주세요.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade300),
                    ),
                  if (iapState.errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '결제 상태 메시지: ${iapState.errorMessage}',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade200),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (hasSubscription)
              StreamBuilder<int>(
                stream: Stream.periodic(
                  const Duration(minutes: 1),
                  (value) => value,
                ),
                builder: (context, snapshot) {
                  final remainLabel = remainingDaysLabel(nearestExpiresAtUtc);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.amber.withValues(alpha: 0.16),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '구독 만료까지',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade100,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          remainLabel,
                          style: TextStyle(
                            fontSize: 46,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                            color: Colors.amber.shade200,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            FilledButton(
              onPressed: openSubscriptionManagement,
              child: const Text('구독 관리'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
