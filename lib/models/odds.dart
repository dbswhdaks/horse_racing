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

  /// 확정배당율종합(API301) 한 줄. 순서무관 승식(QNL·QPL·TLA)은 출주번호 오름차순이다.
  factory Odds.fromDividendJson(Map<String, dynamic> json) {
    return Odds(
      betType: json['pool']?.toString() ?? '',
      horseNo1: _toInt(json['chulNo']),
      horseNo2: _toInt(json['chulNo2']),
      horseNo3: _toInt(json['chulNo3']),
      rate: _toDouble(json['odds']),
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
