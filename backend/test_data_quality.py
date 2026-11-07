from __future__ import annotations

import unittest

from data_quality import (
    column_missing_rates,
    has_generated_result_fingerprint,
    race_integrity_issues,
    synthetic_race_keys,
)


def _result(horse_no: int, rank: int, *, generated: bool = False) -> dict:
    row = {
        "meet": "1",
        "race_date": "20260308",
        "race_no": 1,
        "horse_no": horse_no,
        "rank": rank,
        "race_time": "1:12.3",
        "s1f": "",
        "g3f": "",
        "pass_order": "",
    }
    if generated:
        row.update(
            race_time="1:12.34",
            s1f="13.2",
            g3f="38.1",
            pass_order=f"{horse_no}-{horse_no}-2-1",
        )
    return row


class DataQualityTest(unittest.TestCase):
    def test_generated_fingerprint_requires_all_signals(self) -> None:
        generated = _result(1, 1, generated=True)
        self.assertTrue(has_generated_result_fingerprint(generated))
        for field in ("race_time", "s1f", "g3f", "pass_order"):
            changed = dict(generated)
            changed[field] = ""
            self.assertFalse(has_generated_result_fingerprint(changed), field)

    def test_quarantines_only_race_level_majority(self) -> None:
        generated = [_result(i, i, generated=True) for i in range(1, 6)]
        actual = [_result(i, i) for i in range(1, 6)]
        self.assertEqual(synthetic_race_keys(generated), {("1", "20260308", 1)})
        self.assertEqual(synthetic_race_keys(actual), set())
        self.assertEqual(synthetic_race_keys(generated[:3] + actual[3:]), set())

    def test_integrity_requires_matching_unique_field_and_top3(self) -> None:
        entries = [
            {
                "meet": "1",
                "race_date": "20260308",
                "race_no": 1,
                "horse_no": i,
            }
            for i in range(1, 6)
        ]
        clean = [_result(i, i) for i in range(1, 6)]
        self.assertEqual(race_integrity_issues(entries, clean), {})

        broken = clean[:-1]
        broken[2]["rank"] = 2
        issues = race_integrity_issues(entries, broken)[("1", "20260308", 1)]
        self.assertIn("entry_result_horse_no_mismatch", issues)
        self.assertIn("rank_2_count_2", issues)
        self.assertIn("rank_3_count_0", issues)

    def test_missing_rates_treat_zero_as_missing(self) -> None:
        rates = column_missing_rates(
            [{"a": 1, "b": ""}, {"a": 0, "b": "x"}], ("a", "b")
        )
        self.assertEqual(rates, {"a": 0.5, "b": 0.5})


if __name__ == "__main__":
    unittest.main()
