"""학습·평가에 사용할 경주 결과의 품질 판정.

운영 DB 행은 삭제하지 않는다. 과거 개발용 생성 스크립트가 만든 결과를
여러 독립적인 지문이 경주 대부분에서 동시에 나타날 때만 보수적으로
격리한다.
"""

from __future__ import annotations

import re
from collections import Counter, defaultdict
from typing import Any, Iterable

RaceKey = tuple[str, str, int]

_GENERATED_TIME = re.compile(r"^\d+:\d{2}\.\d{2}$")
_GENERATED_PASS_ORDER = re.compile(r"^\d+(?:-\d+){3}$")
_ONE_DECIMAL = re.compile(r"^\d+\.\d$")


def _to_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def race_key(row: dict[str, Any]) -> RaceKey | None:
    meet = str(row.get("meet", "")).strip()
    race_date = str(row.get("race_date", "")).strip()
    race_no = _to_int(row.get("race_no"))
    if not meet or len(race_date) != 8 or not race_date.isdigit() or race_no <= 0:
        return None
    return (meet, race_date, race_no)


def has_generated_result_fingerprint(row: dict[str, Any]) -> bool:
    """개발용 생성기의 한 행 지문인지 판정한다.

    실제 KRA 값 하나와 우연히 겹칠 수 있으므로 네 조건을 모두 요구한다.
    """
    race_time = str(row.get("race_time", "")).strip()
    s1f_text = str(row.get("s1f", "")).strip()
    g3f_text = str(row.get("g3f", "")).strip()
    pass_order = str(row.get("pass_order", "")).strip()
    s1f = _to_float(s1f_text, -1.0)
    g3f = _to_float(g3f_text, -1.0)
    return (
        bool(_GENERATED_TIME.fullmatch(race_time))
        and bool(_GENERATED_PASS_ORDER.fullmatch(pass_order))
        and bool(_ONE_DECIMAL.fullmatch(s1f_text))
        and bool(_ONE_DECIMAL.fullmatch(g3f_text))
        and 12.5 <= s1f <= 14.5
        and 36.0 <= g3f <= 40.0
    )


def synthetic_race_keys(
    rows: Iterable[dict[str, Any]],
    *,
    minimum_rows: int = 5,
    minimum_ratio: float = 0.80,
) -> set[RaceKey]:
    """합성 지문이 경주 대부분에서 나타나는 경주만 격리한다."""
    totals: Counter[RaceKey] = Counter()
    fingerprinted: Counter[RaceKey] = Counter()
    for row in rows:
        key = race_key(row)
        if key is None:
            continue
        totals[key] += 1
        if has_generated_result_fingerprint(row):
            fingerprinted[key] += 1
    return {
        key
        for key, total in totals.items()
        if total >= minimum_rows
        and fingerprinted[key] / total >= minimum_ratio
    }


def race_integrity_issues(
    entries: Iterable[dict[str, Any]],
    results: Iterable[dict[str, Any]],
) -> dict[RaceKey, tuple[str, ...]]:
    """출마표와 결과가 Top3 평가에 안전한지 경주 단위로 검사한다."""
    entry_nos: dict[RaceKey, list[int]] = defaultdict(list)
    result_nos: dict[RaceKey, list[int]] = defaultdict(list)
    result_ranks: dict[RaceKey, list[int]] = defaultdict(list)

    for row in entries:
        key = race_key(row)
        horse_no = _to_int(row.get("horse_no"))
        if key is not None and horse_no > 0:
            entry_nos[key].append(horse_no)
    for row in results:
        key = race_key(row)
        horse_no = _to_int(row.get("horse_no"))
        if key is None:
            continue
        if horse_no > 0:
            result_nos[key].append(horse_no)
        rank = _to_int(row.get("rank"))
        if rank > 0:
            result_ranks[key].append(rank)

    issues: dict[RaceKey, tuple[str, ...]] = {}
    for key in set(entry_nos) | set(result_nos):
        found: list[str] = []
        e_nos = entry_nos.get(key, [])
        r_nos = result_nos.get(key, [])
        ranks = result_ranks.get(key, [])
        if len(e_nos) != len(set(e_nos)):
            found.append("duplicate_entry_horse_no")
        if len(r_nos) != len(set(r_nos)):
            found.append("duplicate_result_horse_no")
        if set(e_nos) != set(r_nos):
            found.append("entry_result_horse_no_mismatch")
        for rank in (1, 2, 3):
            if ranks.count(rank) != 1:
                found.append(f"rank_{rank}_count_{ranks.count(rank)}")
        if found:
            issues[key] = tuple(found)
    return issues


def column_missing_rates(
    rows: Iterable[dict[str, Any]], columns: Iterable[str]
) -> dict[str, float]:
    materialized = list(rows)
    if not materialized:
        return {column: 1.0 for column in columns}
    rates: dict[str, float] = {}
    for column in columns:
        missing = 0
        for row in materialized:
            value = row.get(column)
            if value is None or str(value).strip() in ("", "0", "0.0"):
                missing += 1
        rates[column] = round(missing / len(materialized), 4)
    return rates
