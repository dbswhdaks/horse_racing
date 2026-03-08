class RaceEntry {
  final int raceNo;
  final int horseNo;
  final int horseRegNo;
  final String horseName;
  final String birthPlace;
  final String sex;
  final int age;
  final String jockeyName;
  final String trainerName;
  final String ownerName;
  final double weight;
  final double rating;
  final int totalPrize;
  final int recentPrize;
  final int winCount;
  final int placeCount;
  final int totalRaces;
  final double horseWeight;

  RaceEntry({
    this.raceNo = 0,
    required this.horseNo,
    this.horseRegNo = 0,
    required this.horseName,
    required this.birthPlace,
    required this.sex,
    required this.age,
    required this.jockeyName,
    required this.trainerName,
    required this.ownerName,
    required this.weight,
    required this.rating,
    required this.totalPrize,
    required this.recentPrize,
    required this.winCount,
    required this.placeCount,
    required this.totalRaces,
    required this.horseWeight,
  });

  factory RaceEntry.fromJson(Map<String, dynamic> json) {
    final chulNo = _toInt(json['chulNo'] ?? json['startNo']);
    final hrNo = _toInt(json['hrNo']);

    return RaceEntry(
      raceNo: _toInt(json['rcNo'] ?? json['race_no']),
      horseNo: chulNo > 0 ? chulNo : hrNo,
      horseRegNo: hrNo,
      horseName: _str(json['hrName'] ?? json['hrNm'] ?? json['horseName'] ?? ''),
      birthPlace: _str(json['prd'] ?? json['birthPlc'] ?? json['prodCntryNm'] ?? ''),
      sex: _str(json['sex'] ?? json['sexNm'] ?? json['sexCd'] ?? ''),
      age: _toInt(json['age']),
      jockeyName: _cleanName(
          _str(json['jkName'] ?? json['jkNm'] ?? json['jockyNm'] ?? '')),
      trainerName: _str(json['trName'] ?? json['trNm'] ?? json['trnrNm'] ?? ''),
      ownerName: _str(json['owName'] ?? json['owNm'] ?? json['ownrNm'] ?? ''),
      weight: _toDouble(json['wgBudam'] ?? json['wght'] ?? json['brdnWt']),
      rating: _toDouble(json['rating'] ?? json['rtngPt']),
      totalPrize: _toInt(json['chaksunT'] ?? json['totalPrz'] ?? json['totalPrzAmt']),
      recentPrize: _toInt(json['chaksunY'] ?? json['recentPrz'] ?? json['rcnt1YPrzAmt']),
      winCount: _toInt(json['ord1CntT'] ?? json['ord1Cnt']),
      placeCount: _toInt(json['ord2CntT'] ?? json['ord2Cnt']),
      totalRaces: _toInt(json['rcCntT'] ?? json['totalCnt'] ?? json['strtCnt']),
      horseWeight: _toDouble(json['hrWght'] ?? json['rcHrsWt'] ?? 0),
    );
  }

  double get winRate => totalRaces > 0 ? winCount / totalRaces * 100 : 0;
  double get placeRate =>
      totalRaces > 0 ? (winCount + placeCount) / totalRaces * 100 : 0;

  String get sexLabel {
    switch (sex) {
      case '수':
      case 'M':
        return '수';
      case '암':
      case 'F':
        return '암';
      case '거':
      case 'G':
        return '거';
      default:
        return sex;
    }
  }

  static String _str(dynamic v) => v?.toString().trim() ?? '';

  static String _cleanName(String name) {
    return name.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
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
