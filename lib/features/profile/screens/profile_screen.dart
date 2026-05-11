import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/iap_constants.dart';
import '../../purchase/providers/in_app_purchase_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 1분마다 화면을 갱신하여 카운트다운을 최신 상태로 유지한다.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  String _planLabel(String productId) {
    switch (productId) {
      case 'premium_monthly':
        return '프리미엄 월간';
      case 'premium_yearly':
        return '프리미엄 연간';
      default:
        return productId;
    }
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '확인 불가';
    return DateFormat('yyyy.MM.dd HH:mm').format(dateTime.toLocal());
  }

  /// 만료까지 남은 일수 계산. 만료 시 '만료', 당일이면 'D-Day'.
  String _remainingDaysLabel(DateTime? expiresAtUtc) {
    if (expiresAtUtc == null) return '-';
    final nowUtc = _now.toUtc();
    final diff = expiresAtUtc.difference(nowUtc);
    if (diff.isNegative) return '만료';
    final remainDays = (diff.inHours / 24).ceil();
    if (remainDays <= 0) return 'D-Day';
    return 'D-$remainDays';
  }

  Future<void> _copyOrderId(String? orderId) async {
    final value = orderId?.trim() ?? '';
    if (value.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('복사할 주문 아이디가 없습니다.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('주문 아이디를 복사했습니다.')),
    );
  }

  Future<void> _openSubscriptionManagement() async {
    final uri = Uri.parse('https://play.google.com/store/account/subscriptions');
    final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구독 관리 페이지를 열 수 없습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final iapState = ref.watch(inAppPurchaseProvider);

    final activeSubscriptionIds = iapState.purchasedProductIds
        .where(IapConstants.subscriptionProductIds.contains)
        .toList()
      ..sort();
    final entitlements = <String, SubscriptionEntitlement>{
      for (final e in iapState.entitlementByProductId.values)
        if (activeSubscriptionIds.contains(e.productId)) e.productId: e,
    };
    final hasSubscription = activeSubscriptionIds.isNotEmpty;

    DateTime? nearestExpiresAtUtc;
    for (final e in entitlements.values) {
      if (nearestExpiresAtUtc == null ||
          e.expiresAtUtc.isBefore(nearestExpiresAtUtc)) {
        nearestExpiresAtUtc = e.expiresAtUtc;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('프로필')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (hasSubscription) ...[
              _CountdownCard(label: _remainingDaysLabel(nearestExpiresAtUtc)),
              const SizedBox(height: 14),
            ],
            _buildStatusCard(
              hasSubscription: hasSubscription,
              activeSubscriptionIds: activeSubscriptionIds,
              entitlements: entitlements,
              errorMessage: iapState.errorMessage,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _openSubscriptionManagement,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('구독 관리'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required bool hasSubscription,
    required List<String> activeSubscriptionIds,
    required Map<String, SubscriptionEntitlement> entitlements,
    required String? errorMessage,
  }) {
    return Container(
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
          const SizedBox(height: 12),
          if (hasSubscription)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이용 중 플랜: ${activeSubscriptionIds.map(_planLabel).join(', ')}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade300),
                ),
                const SizedBox(height: 10),
                ...activeSubscriptionIds.map((productId) {
                  final entitlement = entitlements[productId];
                  return _SubscriptionDetailTile(
                    planName: _planLabel(productId),
                    orderId: entitlement?.orderId,
                    startedAtLabel: _formatDate(entitlement?.startedAtUtc),
                    expiresAtLabel: _formatDate(entitlement?.expiresAtUtc),
                    onCopyOrderId: () => _copyOrderId(entitlement?.orderId),
                  );
                }),
              ],
            )
          else
            Text(
              '아직 활성화된 구독이 없습니다. 구독 결제 화면에서 플랜을 선택해 주세요.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade300),
            ),
          if (errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              '결제 상태 메시지: $errorMessage',
              style: TextStyle(fontSize: 12, color: Colors.red.shade200),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.amber.withValues(alpha: 0.16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
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
            label,
            style: TextStyle(
              fontSize: 48,
              height: 1.0,
              fontWeight: FontWeight.w900,
              color: Colors.amber.shade200,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionDetailTile extends StatelessWidget {
  const _SubscriptionDetailTile({
    required this.planName,
    required this.orderId,
    required this.startedAtLabel,
    required this.expiresAtLabel,
    required this.onCopyOrderId,
  });

  final String planName;
  final String? orderId;
  final String startedAtLabel;
  final String expiresAtLabel;
  final VoidCallback onCopyOrderId;

  @override
  Widget build(BuildContext context) {
    final orderIdText = (orderId == null || orderId!.trim().isEmpty)
        ? '확인 불가'
        : orderId!.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13, height: 1.4),
                    children: [
                      const TextSpan(
                        text: '구매 아이디  ',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: orderIdText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: onCopyOrderId,
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: '구매 아이디 복사',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _LabeledRow(label: '구매 시작일', value: startedAtLabel),
          const SizedBox(height: 2),
          _LabeledRow(label: '구매 종료일', value: expiresAtLabel),
        ],
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
