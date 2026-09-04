import unittest
from unittest.mock import patch

import httpx

from app.supabase_client import _execute_with_retry


class _Query:
    def __init__(self, outcomes):
        self._outcomes = list(outcomes)
        self.calls = 0

    def execute(self):
        self.calls += 1
        outcome = self._outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


class ExecuteWithRetryTest(unittest.TestCase):
    """예약 실행이 일시적인 연결 끊김으로 통째로 죽지 않아야 한다."""

    def test_returns_result_without_retrying_on_success(self):
        query = _Query(["ok"])
        with patch("app.supabase_client.time.sleep") as sleep:
            self.assertEqual(_execute_with_retry(lambda: query), "ok")
        self.assertEqual(query.calls, 1)
        sleep.assert_not_called()

    def test_retries_transport_error_then_succeeds(self):
        query = _Query([httpx.RemoteProtocolError("Server disconnected"), "ok"])
        with patch("app.supabase_client.time.sleep"):
            self.assertEqual(_execute_with_retry(lambda: query), "ok")
        self.assertEqual(query.calls, 2)

    def test_raises_after_exhausting_attempts(self):
        query = _Query([httpx.ConnectError("boom")] * 3)
        with patch("app.supabase_client.time.sleep"):
            with self.assertRaises(httpx.ConnectError):
                _execute_with_retry(lambda: query)
        self.assertEqual(query.calls, 3)

    def test_does_not_retry_non_transport_error(self):
        # 스키마·데이터 오류는 다시 시도해도 같으므로 즉시 올린다.
        query = _Query([ValueError("bad column")])
        with patch("app.supabase_client.time.sleep"):
            with self.assertRaises(ValueError):
                _execute_with_retry(lambda: query)
        self.assertEqual(query.calls, 1)


if __name__ == "__main__":
    unittest.main()
