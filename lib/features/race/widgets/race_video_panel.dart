import 'package:flutter/material.dart';

import '../../../core/widgets/in_app_webview_screen.dart';
import '../../../core/services/kra_video_service.dart';
import '../../../core/theme/app_theme.dart';

class RaceVideoPanel extends StatelessWidget {
  const RaceVideoPanel({
    super.key,
    required this.links,
    this.showParadeButton = true,
  });

  final RaceVideoLinks links;
  final bool showParadeButton;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.live_tv_rounded,
                size: 18,
                color: Colors.lightBlue.shade200,
              ),
              const SizedBox(width: 8),
              const Text(
                'KRA 경주 영상',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (showParadeButton) ...[
                Expanded(
                  child: _VideoActionButton(
                    icon: Icons.directions_run_rounded,
                    label: '경주로 입장',
                    onTap: () => _openExternal(context, links.paradeUrl),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _VideoActionButton(
                  icon: Icons.play_circle_fill_rounded,
                  label: '경주영상',
                  onTap: () => _openExternal(context, links.liveUrl),
                  isPrimary: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '출처:한국마사회',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError(context, '링크 형식이 올바르지 않습니다.');
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InAppWebViewScreen(url: uri.toString(), title: '경주 영상'),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _VideoActionButton extends StatelessWidget {
  const _VideoActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);

    if (isPrimary) {
      return SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 17),
          label: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF5350),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.lightBlue.shade100,
          side: BorderSide(
            color: Colors.lightBlue.shade200.withValues(alpha: 0.5),
          ),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}
