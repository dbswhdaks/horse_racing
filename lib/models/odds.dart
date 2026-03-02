class Odds {
  final String betType;
  final int horseNo1;
  final int horseNo2;
  final int horseNo3;
  final double rate;

  Odds({
    required this.betType,
    required this.horseNo1,
    required this.horseNo2,
    required this.horseNo3,
    required this.rate,
  });

  factory Odds.fromJson(Map<String, dynamic> json) {
    return Odds(
      betType: _str(json['betType'] ?? json['bettKindCd'] ?? ''),
      horseNo1: _toInt(json['hrNo1'] ?? json['winHrsNo']),
      horseNo2: _toInt(json['hrNo2'] ?? json['plcHrsNo']),
      horseNo3: _toInt(json['hrNo3'] ?? json['trdHrsNo']),
      rate: _toDouble(json['rate'] ?? json['bettRt']),
    );
  }

  String get betTypeLabel {
    switch (betType) {
      case 'WIN':
        return '단승';
      case 'PLC':
        return '연승';
      case 'QNL':
        return '복승';
      case 'EXA':
        return '쌍승';
      case 'TLA':
        return '삼복승';
      case 'TRI':
        return '삼쌍승';
      default:
        return betType;
    }
  }

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

class WinOdds {
  final int horseNo;
  final double winRate;
  final double placeRate;

  WinOdds({
    required this.horseNo,
    required this.winRate,
    required this.placeRate,
  });
}
