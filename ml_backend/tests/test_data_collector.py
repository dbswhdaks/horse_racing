import unittest
from unittest.mock import patch

from app.data_collector import _get_json


class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self._payload


def _call_with(payload):
    with patch("app.data_collector.requests.get", return_value=_FakeResponse(payload)):
        return _get_json("/API72_2/racePlan_2", {})


class GetJsonTest(unittest.TestCase):
    """KRA API 는 응답 형태가 일정하지 않아 방어적으로 파싱해야 한다."""

    def test_returns_list_when_multiple_items(self):
        payload = {"response": {"body": {"items": {"item": [{"rcNo": 1}, {"rcNo": 2}]}}}}
        self.assertEqual(_call_with(payload), [{"rcNo": 1}, {"rcNo": 2}])

    def test_wraps_single_item_dict_in_list(self):
        payload = {"response": {"body": {"items": {"item": {"rcNo": 1}}}}}
        self.assertEqual(_call_with(payload), [{"rcNo": 1}])

    def test_empty_string_items_returns_empty_list(self):
        # 경주가 없는 날짜의 실제 응답 형태.
        payload = {"response": {"body": {"items": "", "totalCount": 0}}}
        self.assertEqual(_call_with(payload), [])

    def test_empty_string_body_returns_empty_list(self):
        payload = {"response": {"body": ""}}
        self.assertEqual(_call_with(payload), [])

    def test_missing_item_key_returns_empty_list(self):
        payload = {"response": {"body": {"items": {}}}}
        self.assertEqual(_call_with(payload), [])

    def test_non_dict_payload_returns_empty_list(self):
        self.assertEqual(_call_with([1, 2, 3]), [])


if __name__ == "__main__":
    unittest.main()
