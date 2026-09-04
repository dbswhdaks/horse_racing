import unittest
from unittest.mock import patch

from app import sync_service


class MonthRacePlanCacheTest(unittest.TestCase):
    """응답이 느린 경마장에서 월 일정을 반복 조회하면 백필이 타임아웃으로 막힌다."""

    def setUp(self):
        sync_service._month_plan_cache.clear()

    def test_month_plan_is_fetched_once_per_meet_and_month(self):
        plan = [{"rcDate": "20260904"}, {"rcDate": "20260905"}]
        with patch.object(sync_service, "_get_json", return_value=plan) as get_json:
            for date in ("20260904", "20260905", "20260906"):
                sync_service.has_scheduled_race("3", date)

        self.assertEqual(get_json.call_count, 1)

    def test_separate_months_are_fetched_separately(self):
        with patch.object(sync_service, "_get_json", return_value=[]) as get_json:
            sync_service.month_race_plan("1", "202608")
            sync_service.month_race_plan("1", "202609")
            sync_service.month_race_plan("1", "202608")

        self.assertEqual(get_json.call_count, 2)


class HasScheduledRaceTest(unittest.TestCase):
    def setUp(self):
        sync_service._month_plan_cache.clear()

    def test_true_when_date_is_in_month_plan(self):
        plan = [{"rcDate": "20260904"}, {"rcDate": "20260905"}]
        with patch.object(sync_service, "_get_json", return_value=plan):
            self.assertTrue(sync_service.has_scheduled_race("1", "20260905"))

    def test_false_when_date_is_absent_from_month_plan(self):
        plan = [{"rcDate": "20260904"}]
        with patch.object(sync_service, "_get_json", return_value=plan):
            self.assertFalse(sync_service.has_scheduled_race("1", "20260905"))

    def test_true_when_month_plan_is_unavailable(self):
        # 판단 근거가 없으면 건너뛰지 않고 기존처럼 일자별로 조회한다.
        with patch.object(sync_service, "_get_json", return_value=[]):
            self.assertTrue(sync_service.has_scheduled_race("1", "20260905"))


if __name__ == "__main__":
    unittest.main()
