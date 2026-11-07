from __future__ import annotations

import unittest

from entry_features import AsOfFeatureIndex, parse_race_time_seconds


def _row(
    race_date: str,
    rank: int,
    *,
    meet: str = "1",
    race_no: int = 1,
    horse_name: str = "테스트마",
) -> dict:
    return {
        "meet": meet,
        "race_date": race_date,
        "race_no": race_no,
        "horse_no": rank,
        "horse_name": horse_name,
        "jockey_name": "테스트기수",
        "trainer_name": "테스트조교사",
        "rank": rank,
        "distance": 1200,
        "race_time": f"{71 + rank * 0.5:.1f}",
        "weight": 55.0,
        "horse_weight": 470.0,
        "pass_order": "",
    }


class SafeEntryFeaturesTest(unittest.TestCase):
    def test_race_time_parser(self) -> None:
        self.assertAlmostEqual(parse_race_time_seconds("1:12.3"), 72.3)
        self.assertAlmostEqual(parse_race_time_seconds("59.9"), 59.9)
        self.assertEqual(parse_race_time_seconds("0.0"), 0.0)
        self.assertEqual(parse_race_time_seconds("bad"), 0.0)

    def test_future_rows_do_not_change_past_features(self) -> None:
        past = [
            _row("20260101", 1, race_no=1),
            _row("20260108", 3, race_no=1),
            _row("20260115", 2, race_no=1),
        ]
        future = [
            _row("20261201", 10, race_no=1),
            _row("20261208", 10, race_no=1),
        ]
        query = dict(
            race_date="20260201",
            meet="1",
            horse_name="테스트마",
            jockey_name="테스트기수",
            trainer_name="테스트조교사",
            distance=1200,
            carried_weight=56.0,
            horse_weight=470.0,
            horse_no=2,
            field_size=10,
        )
        before = AsOfFeatureIndex(past).features_for(**query)
        after = AsOfFeatureIndex(past + future).features_for(**query)
        self.assertEqual(before, after)

    def test_gate_and_burden_are_bounded(self) -> None:
        index = AsOfFeatureIndex([_row("20260101", 1)])
        scores = index.features_for(
            race_date="20260201",
            meet="1",
            horse_name="테스트마",
            jockey_name="테스트기수",
            trainer_name="테스트조교사",
            distance=1200,
            carried_weight=58.0,
            horse_weight=450.0,
            horse_no=10,
            field_size=10,
        )
        self.assertGreaterEqual(scores.burden, 0.0)
        self.assertLessEqual(scores.burden, 1.0)
        self.assertEqual(scores.gate, 0.0)


if __name__ == "__main__":
    unittest.main()
