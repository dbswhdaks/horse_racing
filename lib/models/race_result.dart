class RaceResult {
  final int rank;
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
    required this.rank,
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
    return RaceResult(
      rank: _toInt(json['ord'] ?? json['rankNo']),
      horseNo: _toInt(json['hrNo'] ?? json['chulNo']),
      horseName: _str(json['hrNm']),
      jockeyName: _str(json['jkNm'] ?? json['jockyNm'] ?? ''),
      trainerName: _str(json['trNm'] ?? json['trnrNm'] ?? ''),
      raceTime: _str(json['rcTime'] ?? json['rcTimeTxt'] ?? ''),
      weight: _toDouble(json['wght'] ?? json['brdnWt']),
      horseWeight: _toDouble(json['hrWght'] ?? json['rcHrsWt'] ?? 0),
      rankDiff: _str(json['ordDiff'] ?? json['rcOrdDiff'] ?? ''),
      winOdds: _toDouble(json['winOdds'] ?? json['winBettRt']),
      placeOdds: _toDouble(json['plcOdds'] ?? json['plcBettRt']),
      s1f: _str(json['s1f'] ?? json['s1fTm'] ?? ''),
      g3f: _str(json['g3f'] ?? json['g3fTm'] ?? ''),
      passOrder: _str(json['ordBigo'] ?? json['passOrdTxt'] ?? ''),
      distance: _toInt(json['rcDist']),
      raceDate: _str(json['rcDate'] ?? json['rcDt'] ?? ''),
      meet: _str(json['meet'] ?? ''),
    );
  }

  String get rankLabel {
    if (rank <= 0) return '-';
    if (rank == 1) return '1착';
    if (rank == 2) return '2착';
    if (rank == 3) return '3착';
    return '$rank착';
  }

  bool get isWin => rank == 1;
  bool get isPlace => rank >= 1 && rank <= 3;

  static String _str(dynamic v) => v?.toString() ?? '';
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
}
