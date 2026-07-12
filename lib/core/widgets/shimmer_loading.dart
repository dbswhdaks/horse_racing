import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

class ShimmerLoading extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade800,
      highlightColor: Colors.grey.shade600,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class ShimmerCardList extends StatelessWidget {
  final int count;
  final double cardHeight;

  const ShimmerCardList({
    super.key,
    this.count = 5,
    this.cardHeight = 100,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ShimmerLoading(height: cardHeight),
      ),
    );
  }
}

/// 메인 화면 로딩용 Shimmer 위젯.
///
/// - 상단: 회전 sweep 링 + "경주 정보 불러오는 중" 헤더 + 애니메이션 도트
/// - 하단: RaceCard 레이아웃과 동일한 스켈레톤 + 좌→우 shimmer sweep
class ShimmerRaceList extends StatefulWidget {
  const ShimmerRaceList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  State<ShimmerRaceList> createState() => _ShimmerRaceListState();
}

class _ShimmerRaceListState extends State<ShimmerRaceList>
    with TickerProviderStateMixin {
  late final AnimationController _sweep;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LoadingHeader(sweep: _sweep, pulse: _pulse),
        const SizedBox(height: 14),
        for (int i = 0; i < widget.itemCount; i++) ...[
          _ShimmerRaceCard(sweep: _sweep, index: i),
          if (i != widget.itemCount - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ─── 상단 로딩 헤더 ─────────────────────────────────────────────

class _LoadingHeader extends StatelessWidget {
  const _LoadingHeader({required this.sweep, required this.pulse});

  final AnimationController sweep;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final glow = 0.12 + pulse.value * 0.18;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.accentGold.withValues(alpha: 0.06 + pulse.value * 0.04),
                AppTheme.primaryGreen
                    .withValues(alpha: 0.08 + pulse.value * 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.accentGold.withValues(alpha: glow),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentGold.withValues(alpha: glow * 0.4),
                blurRadius: 18,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Row(
            children: [
              _SpinningRing(controller: sweep),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '경주 정보 불러오는 중',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '잠시만 기다려주세요',
                      style: TextStyle(
                        color: Color(0xFF8B949E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _AnimatedDots(controller: pulse),
            ],
          ),
        );
      },
    );
  }
}

/// 회전하는 sweep 그라데이션 링 안에 트로피 아이콘 (경마Plus 브랜드).
class _SpinningRing extends StatelessWidget {
  const _SpinningRing({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Transform.rotate(
          angle: controller.value * 6.2831853, // 2π
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Color(0x00FFB300),
                  Color(0x33FFB300),
                  Color(0xFFFFB300),
                ],
                stops: [0.0, 0.7, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceDark,
                  shape: BoxShape.circle,
                ),
                child: Transform.rotate(
                  // 링과 반대로 돌려서 아이콘은 정지된 것처럼 보이게
                  angle: -controller.value * 6.2831853,
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    size: 14,
                    color: AppTheme.accentGold,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 3개의 도트가 순차적으로 밝아지는 인디케이터.
class _AnimatedDots extends StatelessWidget {
  const _AnimatedDots({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (controller.value + i * 0.25) % 1.0;
            final t = (phase < 0.5) ? phase * 2 : (1 - phase) * 2;
            final alpha = (0.25 + t * 0.75).clamp(0.25, 1.0);
            final scale = 0.7 + t * 0.35;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppTheme.accentGold.withValues(alpha: alpha),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            AppTheme.accentGold.withValues(alpha: alpha * 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── 카드 스켈레톤 (RaceCard 레이아웃 미러링) ─────────────────

class _ShimmerRaceCard extends StatelessWidget {
  const _ShimmerRaceCard({required this.sweep, required this.index});

  final AnimationController sweep;
  final int index;

  static const Color _baseColor = Color(0xFF2A2A2A);
  static const Color _borderColor = Color(0xFF2E2E2E);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: _ShimmerSweep(
        controller: sweep,
        indexOffset: index,
        child: Column(
          children: [
            // 상단: 번호 배지 · 타이틀/서브타이틀 · 시간
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(width: 42, height: 42, radius: 11),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _bar(width: 90, height: 16, radius: 4),
                            const SizedBox(width: 8),
                            _bar(width: 42, height: 16, radius: 5),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _bar(width: 160, height: 12, radius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _bar(width: 52, height: 20, radius: 4),
                      const SizedBox(height: 4),
                      _bar(width: 40, height: 11, radius: 3),
                    ],
                  ),
                ],
              ),
            ),
            // 하단: 미니 스탯 + 액션 칩 영역
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  _bar(width: 13, height: 13, radius: 3),
                  const SizedBox(width: 4),
                  _bar(width: 30, height: 12, radius: 3),
                  const SizedBox(width: 10),
                  _bar(width: 13, height: 13, radius: 3),
                  const SizedBox(width: 4),
                  _bar(width: 40, height: 12, radius: 3),
                  const Spacer(),
                  _bar(width: 56, height: 22, radius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar({
    required double width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _baseColor,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 자식 위에 좌→우 하이라이트 그라데이션을 덧씌워 shimmer sweep 효과.
///
/// - `BlendMode.srcATop`: 자식의 불투명 영역(스켈레톤 바)에만 하이라이트가 얹힌다.
/// - `indexOffset`: 카드마다 위상차를 줘 파도처럼 순차 반짝임 연출.
class _ShimmerSweep extends StatelessWidget {
  const _ShimmerSweep({
    required this.controller,
    required this.child,
    this.indexOffset = 0,
  });

  final AnimationController controller;
  final Widget child;
  final int indexOffset;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // 0.0 ~ 1.0 을 -1.5 ~ 2.5 범위로 확장해 하이라이트가 밖에서 밖으로 흐르게.
        final phase = (controller.value + indexOffset * 0.07) % 1.0;
        final dx = -1.5 + phase * 4.0;

        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(dx - 0.6, -0.2),
              end: Alignment(dx + 0.6, 0.2),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.14),
                AppTheme.accentGold.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.06),
                Colors.transparent,
              ],
              stops: const [0.0, 0.30, 0.44, 0.5, 0.56, 0.70, 1.0],
            ).createShader(rect);
          },
          child: child,
        );
      },
    );
  }
}
