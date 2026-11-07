from __future__ import annotations

import unittest
from unittest.mock import patch

from tune_heuristic_predictions import (
    HeuristicParams,
    _evaluate,
    _paired_bootstrap_exact,
    _split_search_holdout_by_date,
    _walk_forward_blocks,
)


def _params() -> HeuristicParams:
    return HeuristicParams(
        w_rating=1,
        w_perf=0,
        w_class_form=0,
        w_pace=0,
        w_condition=0,
        w_market=0,
        w_jockey=0,
        w_recent_form=0,
        w_fitness=0,
        w_trainer=0,
        w_combo=0,
        w_speed=0,
        w_burden=0,
        w_gate=0,
        rating_pow=1,
        prior_weight=1,
        temp_scale=1,
        place_temp_scale=1,
        place_specialist_mix=0,
        place_rating_pow=1,
        reliability_penalty=0,
    )


def _sample(date: str, race_no: int = 1) -> dict:
    return {
        "key": ("1", date, race_no),
        "entries": [{"horse_no": i} for i in range(1, 6)],
        "winner_no": 1,
        "actual_top3": {1, 2, 3},
        "actual_ordered_top3": [1, 2, 3],
    }


class TuningMetricsTest(unittest.TestCase):
    def test_exact_set_and_order_are_separate(self) -> None:
        predictions = [
            {"horse_no": 2, "win_probability": 30, "place_probability": 80},
            {"horse_no": 1, "win_probability": 40, "place_probability": 75},
            {"horse_no": 3, "win_probability": 15, "place_probability": 70},
            {"horse_no": 4, "win_probability": 10, "place_probability": 30},
            {"horse_no": 5, "win_probability": 5, "place_probability": 20},
        ]
        with patch(
            "tune_heuristic_predictions._race_probabilities",
            return_value=predictions,
        ):
            metrics = _evaluate([_sample("20260101")], _params())
        self.assertEqual(metrics["exact_top3_rate"], 1.0)
        self.assertEqual(metrics["ordered_top3_exact"], 0.0)
        self.assertEqual(metrics["top3_overlap"], 1.0)

    def test_date_split_never_splits_same_day(self) -> None:
        samples = [
            _sample("20260101", 1),
            _sample("20260101", 2),
            _sample("20260108", 1),
            _sample("20260115", 1),
            _sample("20260122", 1),
        ]
        search, holdout = _split_search_holdout_by_date(samples, 0.25)
        self.assertEqual({s["key"][1] for s in holdout}, {"20260122"})
        self.assertFalse(
            {s["key"][1] for s in search} & {s["key"][1] for s in holdout}
        )
        blocks = _walk_forward_blocks(samples, 2)
        for block in blocks:
            block_dates = {s["key"][1] for s in block}
            for date in block_dates:
                expected = sum(s["key"][1] == date for s in samples)
                actual = sum(s["key"][1] == date for s in block)
                self.assertEqual(actual, expected)

    def test_paired_bootstrap_reports_exact_difference(self) -> None:
        result = _paired_bootstrap_exact(
            [0, 0, 1, 0],
            [1, 0, 1, 1],
            seed=7,
            iterations=500,
        )
        self.assertEqual(result["races"], 4)
        self.assertEqual(result["difference"], 0.5)
        self.assertLessEqual(result["ci_low"], result["difference"])
        self.assertGreaterEqual(result["ci_high"], result["difference"])


if __name__ == "__main__":
    unittest.main()
