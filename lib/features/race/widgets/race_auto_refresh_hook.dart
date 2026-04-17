import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/race_providers.dart';

class RaceAutoRefreshHook extends ConsumerStatefulWidget {
  const RaceAutoRefreshHook({
    super.key,
    required this.meet,
    required this.date,
    required this.raceNo,
    this.interval = const Duration(seconds: 45),
  });

  final String meet;
  final String date;
  final int raceNo;
  final Duration interval;

  @override
  ConsumerState<RaceAutoRefreshHook> createState() =>
      _RaceAutoRefreshHookState();
}

class _RaceAutoRefreshHookState extends ConsumerState<RaceAutoRefreshHook> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) => _onTick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    if (!_shouldAutoRefreshNow()) return;

    ref.invalidate(racePlanProvider((meet: widget.meet, date: widget.date)));
    ref.invalidate(
      raceStartListProvider((
        meet: widget.meet,
        date: widget.date,
        raceNo: widget.raceNo,
      )),
    );
    ref.invalidate(
      oddsProvider((
        meet: widget.meet,
        date: widget.date,
        raceNo: widget.raceNo,
      )),
    );
    ref.invalidate(
      predictionProvider((
        meet: widget.meet,
        date: widget.date,
        raceNo: widget.raceNo,
      )),
    );
  }

  bool _shouldAutoRefreshNow() {
    final raceStart = _readRaceStartDateTime();
    final now = DateTime.now();

    if (raceStart != null) {
      final windowStart = raceStart.subtract(const Duration(minutes: 40));
      final windowEnd = raceStart.add(const Duration(minutes: 80));
      return now.isAfter(windowStart) && now.isBefore(windowEnd);
    }

    final raceDate = _parseRaceDate(widget.date);
    if (raceDate == null) return false;
    return raceDate.year == now.year &&
        raceDate.month == now.month &&
        raceDate.day == now.day;
  }

  DateTime? _readRaceStartDateTime() {
    final races = ref
        .read(racePlanProvider((meet: widget.meet, date: widget.date)))
        .valueOrNull;
    if (races == null || races.isEmpty) return null;

    for (final race in races) {
      if (race.raceNo != widget.raceNo) continue;
      final start = race.startTime.replaceAll(':', '').trim();
      if (start.length < 3) return null;

      final h = int.tryParse(start.substring(0, start.length - 2));
      final m = int.tryParse(start.substring(start.length - 2));
      final d = _parseRaceDate(widget.date);
      if (h == null || m == null || d == null) return null;
      return DateTime(d.year, d.month, d.day, h, m);
    }
    return null;
  }

  DateTime? _parseRaceDate(String raw) {
    if (raw.length != 8) return null;
    final y = int.tryParse(raw.substring(0, 4));
    final m = int.tryParse(raw.substring(4, 6));
    final d = int.tryParse(raw.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
