"""통과순위 파서와 표본 부족 폴백이 Dart 와 같은지 확인한다."""

from __future__ import annotations

import unittest
from datetime import date

from entry_features import (
    _Record,
    parse_pass_order_style,
    running_style_from_records,
)


def _record(day: date, pass_order: str, field_size: int = 10) -> _Record:
    return _Record(
        day=day,
        race_no=1,
        meet="1",
        rank=3,
        field_size=field_size,
        distance=1400,
        race_time_seconds=72.0,
        carried_weight=55.0,
        horse_weight=470.0,
        pass_order=pass_order,
    )


class ParsePassOrderStyleTest(unittest.TestCase):
    def test_empty(self) -> None:
        self.assertEqual(parse_pass_order_style("", 10), "")
        self.assertEqual(parse_pass_order_style("n/a", 10), "")

    def test_korean_label_wins(self) -> None:
        self.assertEqual(parse_pass_order_style("선행 8-8-8-8", 12), "선행")
        self.assertEqual(parse_pass_order_style("추입형", 10), "추입")

    def test_early_position(self) -> None:
        self.assertEqual(parse_pass_order_style("1-1-1-1", 6), "선행")
        self.assertEqual(parse_pass_order_style("2-2-3-2", 14), "선행")
        self.assertEqual(parse_pass_order_style("3-3-3-3", 12), "선행")
        self.assertEqual(parse_pass_order_style("4-4-3-2", 10), "선입")
        self.assertEqual(parse_pass_order_style("6-5-4-3", 10), "중단")
        self.assertEqual(parse_pass_order_style("8-7-5-3", 10), "추입")


class RunningStyleFromRecordsTest(unittest.TestCase):
    def test_needs_two_samples(self) -> None:
        self.assertEqual(running_style_from_records([]), "")
        self.assertEqual(
            running_style_from_records(
                [
                    _record(date(2026, 1, 1), "1-1-1-1"),
                    _record(date(2026, 1, 8), ""),
                ]
            ),
            "",
        )

    def test_mode_prefers_recent_on_tie(self) -> None:
        records = [
            _record(date(2026, 1, 1), "8-8-7-6"),
            _record(date(2026, 1, 8), "8-7-6-5"),
            _record(date(2026, 1, 15), "1-1-1-1"),
            _record(date(2026, 1, 22), "1-2-2-1"),
            _record(date(2026, 1, 29), "1-1-2-1"),
        ]
        self.assertEqual(running_style_from_records(records), "선행")


if __name__ == "__main__":
    unittest.main()
