import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horse_racing/main.dart';

void main() {
  test('App root can be constructed', () {
    expect(const HorseRacingApp(), isA<Widget>());
  });
}
