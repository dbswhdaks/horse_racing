class Race {
  final String meet;
  final String meetName;
  final String raceDate;
  final int raceNo;
  final String startTime;
  final int distance;
  final String gradeCondition;
  final String raceName;
  final String ageCondition;
  final String sexCondition;
  final String weightCondition;
  final int prize1;
  final int prize2;
  final int prize3;
  final int headCount;

  Race({
    required this.meet,
    required this.meetName,
    required this.raceDate,
    required this.raceNo,
    required this.startTime,
    required this.distance,
    required this.gradeCondition,
    required this.raceName,
    required this.ageCondition,
    required this.sexCondition,
    required this.weightCondition,
    required this.prize1,
    required this.prize2,
    required this.prize3,
    required this.headCount,
  });

  factory Race.fromJson(Map<String, dynamic> json) {
    final rawMeet = _str(json['meet']);
    final code = _meetToCode(rawMeet);
    return Race(
      meet: code,
      meetName: _meetName(code),
      raceDate: _str(json['rcDate'] ?? json['rcDt'] ?? ''),
      raceNo: _toInt(json['rcNo']),
      startTime: _str(json['schStTime'] ?? json['stTime'] ?? ''),
      distance: _toInt(json['rcDist']),
      gradeCondition: _str(json['rank'] ?? json['grdCond'] ?? ''),
      raceName: _str(json['rcName'] ?? json['rcNm'] ?? ''),
      ageCondition: _str(json['ageCond'] ?? ''),
      sexCondition: _str(json['sexCond'] ?? ''),
      weightCondition: _str(json['budam'] ?? json['wghtCond'] ?? ''),
      prize1: _toInt(json['chaksun1'] ?? json['prz1']),
      prize2: _toInt(json['chaksun2'] ?? json['prz2']),
      prize3: _toInt(json['chaksun3'] ?? json['prz3']),
      headCount: _toInt(json['dusu'] ?? json['headCnt'] ?? 0),
    );
  }

  String get gradeLabel {
    if (gradeCondition.isEmpty) return '미정';
    return gradeCondition;
  }

  String get distanceLabel => '${distance}m';

  static String _str(dynamic v) => v?.toString() ?? '';
  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  static const _nameToCode = {'서울': '1', '제주': '2', '부산경남': '3'};
  static const _codeToName = {'1': '서울', '2': '제주', '3': '부산경남'};

  static String _meetToCode(String v) => _nameToCode[v] ?? v;
  static String _meetName(String code) => _codeToName[code] ?? code;
}
