class RaceResult {
  final int raceNo;
  final int rank;
  final String rankRaw;
  final int horseNo;
  final String horseName;
  final String jockeyName;
  final String trainerName;
  final String raceTime;
  final double weight;
  final double horseWeight;
  final String rankDiff;
  final double winOdds;
  final double placeOdds;
  final String s1f;
  final String g3f;
  final String passOrder;
  final int distance;
  final String raceDate;
  final String meet;

  RaceResult({
    this.raceNo = 0,
    required this.rank,
    this.rankRaw = '',
    required this.horseNo,
    required this.horseName,
    required this.jockeyName,
    required this.trainerName,
    required this.raceTime,
    required this.weight,
    required this.horseWeight,
    required this.rankDiff,
    required this.winOdds,
    required this.placeOdds,
    required this.s1f,
    required this.g3f,
    required this.passOrder,
    required this.distance,
    required this.raceDate,
    required this.meet,
  });

  factory RaceResult.fromJson(Map<String, dynamic> json) {
    final rawMeet = _str(json['meet'] ?? json['rccrsNm'] ?? '');
    final meetCode = _meetToCode(rawMeet);
    final rawRk = _str(json['rk'] ?? json['ord'] ?? json['rankNo'] ?? '');
    final parsedRank = int.tryParse(rawRk) ?? 0;

    return RaceResult(
      raceNo: _toInt(json['raceNo'] ?? json['rcNo'] ?? json['race_no']),
      rank: parsedRank,
      rankRaw: rawRk,
      horseNo: _toInt(json['gtno'] ?? json['chulNo'] ?? json['hrNo']),
      horseName: _str(json['hrnm'] ?? json['hrName'] ?? json['hrNm'] ?? ''),
      jockeyName: _cleanName(
          _str(json['jckyNm'] ?? json['jkName'] ?? json['jkNm'] ?? '')),
      trainerName:
          _str(json['trarNm'] ?? json['trName'] ?? json['trNm'] ?? ''),
      raceTime: _fmtTime(json['raceRcd'] ?? json['rcTime'] ?? ''),
      weight: _toDouble(json['burdWgt'] ?? json['wgBudam'] ?? json['wght']),
      horseWeight: _parseHorseWeight(json['rchrWeg'] ?? json['hrWght'] ?? 0),
      rankDiff: _str(json['margin'] ?? json['ordDiff'] ?? ''),
      winOdds: _toDouble(json['winPrice'] ?? json['winOdds']),
      placeOdds: _toDouble(json['placePrice'] ?? json['plcOdds']),
      s1f: _str(json['s1f'] ?? json['s1fTm'] ?? ''),
      g3f: _str(json['g3f'] ?? json['g3fTm'] ?? ''),
      passOrder: _str(json['ordBigo'] ?? json['passOrdTxt'] ?? ''),
      distance: _toInt(json['raceDs'] ?? json['rcDist']),
      raceDate: _str(json['raceDt'] ?? json['rcDate'] ?? ''),
      meet: meetCode,
    );
  }

  String get rankLabel {
    if (rank > 0) return '$rank착';
    if (rankRaw.isNotEmpty) return rankRaw;
    return '-';
  }

  bool get isExcluded =>
      rank <= 0 && rankRaw.isNotEmpty && int.tryParse(rankRaw) == null;

  bool get isWin => rank == 1;
  bool get isPlace => rank >= 1 && rank <= 3;

  static String _str(dynamic v) => v?.toString().trim() ?? '';

  static String _cleanName(String name) {
    return name.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
  }

  static String _fmtTime(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      final s = v.toStringAsFixed(1);
      final parts = s.split('.');
      final sec = int.tryParse(parts[0]) ?? 0;
      final frac = parts.length > 1 ? parts[1] : '0';
      final m = sec ~/ 60;
      final r = sec % 60;
      return m > 0 ? '$m:${r.toString().padLeft(2, '0')}.$frac' : '$r.$frac';
    }
    return v.toString().trim();
  }

  static double _parseHorseWeight(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(RegExp(r'\(.*\)'), '').trim();
    return double.tryParse(s) ?? 0.0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static const _nameToCode = {'서울': '1', '제주': '2', '부산경남': '3'};
  static String _meetToCode(String v) => _nameToCode[v] ?? v;
}
