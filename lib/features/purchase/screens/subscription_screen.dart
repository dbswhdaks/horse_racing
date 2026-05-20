import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/iap_constants.dart';
import '../providers/in_app_purchase_provider.dart';

/// Google Play 앱 상세 페이지(구독 결제는 이 앱에서만 가능).
const String _kPlayStoreAppUrl =
    'https://play.google.com/store/apps/details?id=com.horseracingplus.app';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({
    super.key,
    this.initialProductId = 'premium_monthly',
  });

  final String initialProductId;

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  late String _selectedProductId;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId == 'premium_yearly'
        ? 'premium_yearly'
        : 'premium_monthly';
  }

  Future<void> _openPlayPaymentMethods(BuildContext context) async {
    final uri = Uri.parse('https://play.google.com/store/paymentmethods');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('결제수단 관리 페이지를 열 수 없습니다.')));
    }
  }

  Future<void> _openPlayStoreApp(BuildContext context) async {
    final uri = Uri.parse(_kPlayStoreAppUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Play 페이지를 열 수 없습니다.')),
      );
    }
  }

  /// 웹 환경에서 노출되는 안내 화면.
  /// Google Play Billing은 Android 앱에서만 동작하므로,
  /// 사용자에게 앱 설치(또는 앱에서 결제 진행)를 안내한다.
  Widget _buildWebNoticeScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('구독 결제')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.17)),
                gradient: const LinearGradient(
                  colors: [Color(0xFF141D29), Color(0xFF0F1722)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.smartphone_rounded,
                    color: Colors.amber,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '구독 결제는 Android 앱에서 진행됩니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '경마 Plus 구독은 Google Play 인앱 결제로만 제공되어 웹에서는 결제가 불가합니다.\n'
                    'Android 앱을 설치한 뒤 앱 내 [구독 결제] 화면에서 결제해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.grey.shade300,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 240,
                    child: FilledButton.icon(
                      onPressed: () => _openPlayStoreApp(context),
                      icon: const Icon(Icons.shop_rounded, size: 18),
                      label: const Text(
                        'Google Play에서 앱 받기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                      Icon(Icons.workspace_premium_outlined, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '프리미엄 플랜 안내',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _WebPlanRow(label: '월간', priceText: '￦ 9,900원'),
                  const SizedBox(height: 8),
                  _WebPlanRow(
                    label: '연간',
                    priceText: '￦ 99,000원',
                    suffix: '(17% 절약)',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '실제 결제 금액은 Google Play 계정/국가 설정에 따라 달라질 수 있습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 웹(in_app_purchase 미지원)에서는 결제 흐름 대신 Android 앱 안내 화면을 노출.
    if (kIsWeb) {
      return _buildWebNoticeScreen(context);
    }

    final iapState = ref.watch(inAppPurchaseProvider);
    final notifier = ref.read(inAppPurchaseProvider.notifier);
    final productMap = {for (final p in iapState.products) p.id: p};
    final isMonthly = _selectedProductId == 'premium_monthly';
    final isPending = iapState.isPurchasePending;
    final actionText = isMonthly ? '월간 구독 결제' : '연간 구독 결제';
    final hasSubscription = iapState.purchasedProductIds.any(
      IapConstants.subscriptionProductIds.contains,
    );

    String formatPriceSpacing(String raw) {
      return raw.replaceAllMapped(
        RegExp(r'[￦₩]\s*'),
        (match) => '${match.group(0)![0]} ',
      );
    }

    String monthlyText() {
      final monthly = productMap['premium_monthly'];
      if (monthly != null) return '월간 ${formatPriceSpacing(monthly.price)}';
      return '월간 ￦ 9,900원';
    }

    String yearlyText() {
      final yearly = productMap['premium_yearly'];
      if (yearly != null) {
        return '연간 ${formatPriceSpacing(yearly.price)} (17% 절약)';
      }
      return '연간 ￦ 99,000원 (17% 절약)';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('구독 결제')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
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
                      Icon(Icons.payments_outlined, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '결제수단',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shop_rounded, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'Google Play 인앱 결제',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade100,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '결제는 Google Play에서만 진행됩니다. 실제 사용 가능한 결제수단(카드/휴대폰/계좌 등)은 Google Play 계정 설정에 따라 노출됩니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _openPlayPaymentMethods(context),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Google Play 결제수단 관리'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                color: Colors.white.withValues(alpha: 0.03),
              ),
              child: Column(
                children: [
                  _PlanOptionTile(
                    selected: isMonthly,
                    label: monthlyText(),
                    onTap: () =>
                        setState(() => _selectedProductId = 'premium_monthly'),
                  ),
                  const SizedBox(height: 10),
                  _PlanOptionTile(
                    selected: !isMonthly,
                    label: yearlyText(),
                    onTap: () =>
                        setState(() => _selectedProductId = 'premium_yearly'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: isPending
                  ? null
                  : () async {
                      final ok = await notifier.startSubscriptionPurchase(
                        preferredProductId: _selectedProductId,
                      );
                      if (!mounted) return;
                      if (!ok && context.mounted) {
                        final latestState = ref.read(inAppPurchaseProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              latestState.errorMessage ?? '결제를 시작하지 못했습니다.',
                            ),
                          ),
                        );
                      }
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(actionText),
            ),
            const SizedBox(height: 10),
            if (hasSubscription)
              Text(
                '이미 구독이 확인되었습니다. 이전 화면으로 돌아가면 잠금이 해제됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.greenAccent.shade100,
                ),
              ),
            if (iapState.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                '오류: ${iapState.errorMessage}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.red.shade200),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WebPlanRow extends StatelessWidget {
  const _WebPlanRow({
    required this.label,
    required this.priceText,
    this.suffix,
  });

  final String label;
  final String priceText;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.amber.shade200,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          priceText,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 6),
          Text(
            suffix!,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ],
    );
  }
}

class _PlanOptionTile extends StatelessWidget {
  const _PlanOptionTile({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: selected ? const Color(0x33FFB300) : const Color(0x12000000),
          border: Border.all(
            color: selected
                ? const Color(0xCCFFB300)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.amber : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
