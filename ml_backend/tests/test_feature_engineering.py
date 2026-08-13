import unittest

import pandas as pd

from app.feature_engineering import FEATURE_COLUMNS, prepare_xy
from app.trainer import _race_group_time_splits


class FeatureEngineeringTest(unittest.TestCase):
    def test_final_odds_are_not_model_features(self):
        self.assertNotIn("win_odds", FEATURE_COLUMNS)

    def test_rolling_rank_uses_only_previous_races(self):
        rows = []
        for date, rank in (("20260101", 1), ("20260201", 3)):
            rows.append(
                {
                    "meet": "1",
                    "race_date": date,
                    "race_no": 1,
                    "horse_no": 1,
                    "horse_name": "테스트마",
                    "rank": rank,
                    "race_distance": 1200,
                    "burden_weight": 54,
                    "horse_weight": 470,
                    "rating": 70,
                    "age": 4,
                    "sex": "수",
                    "birth_place": "한",
                    "total_races": 10,
                    "win_count": 2,
                    "place_count": 2,
                    "total_prize": 1000,
                    "recent_prize": 100,
                }
            )

        features, _ = prepare_xy(pd.DataFrame(rows))

        self.assertEqual(features.iloc[1]["recent_5_avg_rank"], 1)

    def test_time_split_never_divides_a_race(self):
        keys = pd.Series(
            [
                "1|20260101|1",
                "1|20260101|1",
                "1|20260102|1",
                "1|20260102|1",
                "1|20260103|1",
                "1|20260103|1",
                "1|20260104|1",
                "1|20260104|1",
            ]
        )

        for train, validation in _race_group_time_splits(keys, n_splits=2):
            train_keys = set(keys.iloc[train])
            validation_keys = set(keys.iloc[validation])
            self.assertTrue(train_keys.isdisjoint(validation_keys))


if __name__ == "__main__":
    unittest.main()
