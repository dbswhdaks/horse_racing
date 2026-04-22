import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/in_app_purchase_provider.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key, this.initialProductId = 'premium_monthly'});

  final String initialProductId;

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  late String _selectedProductId;
  String _selectedPaymentMethod = '신용/체크카드';

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId == 'premium_yearly'
        ? 'premium_yearly'
        : 'premium_monthly';
  }

  Future<void> _openPlayPaymentMethods(BuildContext context) async {
    final uri = Uri.parse('https://play.google.com/store/paymentmethods');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('결제수단 관리 페이지를 열 수 없습니다.')),
      );
    }
  }

  Future<String?> _showPaymentMethodPicker(BuildContext context) {
    const options = ['신용/체크카드', '휴대폰 결제', '계좌이체'];
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '결제수단 선택',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              ...options.map(
                (option) => ListTile(
                  title: Text(option),
                  trailing: option == _selectedPaymentMethod
                      ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                      : null,
                  onTap: () => Navigator.of(context).pop(option),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final iapState = ref.watch(inAppPurchaseProvider);
    final notifier = ref.read(inAppPurchaseProvider.notifier);
    final productMap = {for (final p in iapState.products) p.id: p};
    final isMonthly = _selectedProductId == 'premium_monthly';
    final isPending = iapState.isPurchasePending;
    final actionText = isMonthly ? '월간 구독 결제' : '연간 구독 결제';
    final hasSubscription = iapState.purchasedProductIds.any(
      (id) => id == 'premium_monthly' || id == 'premium_yearly',
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
                        '지원 결제수단 (구글플레이)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _PaymentMethodChip(label: '신용/체크카드'),
                      _PaymentMethodChip(label: '휴대폰 결제'),
                      _PaymentMethodChip(label: '계좌이체'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '실제 결제수단 노출은 계정/국가/스토어 설정에 따라 달라질 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _openPlayPaymentMethods(context),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('결제수단 관리'),
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
                    onTap: () => setState(() => _selectedProductId = 'premium_monthly'),
                  ),
                  const SizedBox(height: 10),
                  _PlanOptionTile(
                    selected: !isMonthly,
                    label: yearlyText(),
                    onTap: () => setState(() => _selectedProductId = 'premium_yearly'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: isPending
                  ? null
                  : () async {
                      if (isMonthly) {
                        final selectedMethod = await _showPaymentMethodPicker(
                          context,
                        );
                        if (selectedMethod == null) return;
                        if (!mounted) return;
                        setState(() => _selectedPaymentMethod = selectedMethod);
                      }

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
                        return;
                      }

                      if (isMonthly && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '선택한 결제수단: $_selectedPaymentMethod\n실제 결제는 구글플레이에서 진행됩니다.',
                            ),
                          ),
                        );
                      }
                    },
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
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
            if (hasSubscription || iapState.errorMessage != null)
              const SizedBox(height: 8),
            Text(
              '현재 선택 결제수단: $_selectedPaymentMethod',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodChip extends StatelessWidget {
  const _PaymentMethodChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade200,
        ),
      ),
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
