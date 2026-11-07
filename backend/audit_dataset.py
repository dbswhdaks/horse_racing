"""Supabase 학습 데이터 감사 스크립트.

튜닝 이전에 표본이 충분한지, 배당 컬럼을 사전 피처로 쓸 수 있는지 확인합니다.

사용 예시:
  python backend/audit_dataset.py
  python backend/audit_dataset.py --meet 1 --since 20240101
  python backend/audit_dataset.py --json backend/models/dataset_audit.json
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from datetime import datetime
from typing import Any

from supabase import create_client

from config import SUPABASE_SERVICE_KEY, SUPABASE_URL
from data_quality import (
    column_missing_rates,
    race_integrity_issues,
    synthetic_race_keys,
)
from prediction_constants import MIN_ENTRIES_PER_RACE
from tune_heuristic_predictions import (
    _fetch_all_rows,
    _filter_by_race_date,
    _safe_float,
    _safe_int,
)

RaceKey = tuple[str, str, int]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Supabase 학습 데이터 감사")
    parser.add_argument("--meet", default=None, help="경마장 코드(1/2/3), 미지정 시 전체")
    parser.add_argument("--since", default=None, help="조회 시작일(YYYYMMDD, inclusive)")
    parser.add_argument("--until", default=None, help="조회 종료일(YYYYMMDD, inclusive)")
    parser.add_argument("--json", dest="json_path", default=None, help="감사 결과 JSON 저장 경로")
    return parser.parse_args()


def _race_key(row: dict[str, Any]) -> RaceKey | None:
    race_no = _safe_int(row.get("race_no", 0))
    race_date = str(row.get("race_date", ""))
    meet = str(row.get("meet", ""))
    if race_no <= 0 or len(race_date) != 8 or not meet:
        return None
    return (meet, race_date, race_no)


def _month_of(row: dict[str, Any]) -> str:
    return str(row.get("race_date", ""))[:6] or "unknown"


def _coverage_by_month(rows: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    for row in rows:
        counts[_month_of(row)] += 1
    return dict(sorted(counts.items()))


def _distinct_races(rows: list[dict[str, Any]]) -> set[RaceKey]:
    keys: set[RaceKey] = set()
    for row in rows:
        key = _race_key(row)
        if key is not None:
            keys.add(key)
    return keys


def audit_trainable_races(
    entries: list[dict[str, Any]],
    results: list[dict[str, Any]],
) -> dict[str, Any]:
    """`_build_race_dataset` 과 동일한 조건으로 실제 학습 가능 경주 수를 센다."""
    entries_by_race: dict[RaceKey, int] = defaultdict(int)
    for row in entries:
        key = _race_key(row)
        if key is not None and _safe_int(row.get("horse_no", 0)) > 0:
            entries_by_race[key] += 1

    results_by_race: dict[RaceKey, list[dict[str, Any]]] = defaultdict(list)
    for row in results:
        key = _race_key(row)
        if key is not None:
            results_by_race[key].append(row)

    entry_keys = set(entries_by_race)
    result_keys = set(results_by_race)
    shared = entry_keys & result_keys

    enough_entries = {k for k in shared if entries_by_race[k] >= MIN_ENTRIES_PER_RACE}
    with_winner = {
        k
        for k in enough_entries
        if any(_safe_int(r.get("rank", 0)) == 1 for r in results_by_race[k])
    }

    dropped_small_field = sorted(shared - enough_entries)[:10]
    dropped_no_winner = sorted(enough_entries - with_winner)[:10]

    return {
        "races_with_entries": len(entry_keys),
        "races_with_results": len(result_keys),
        "races_with_both": len(shared),
        "entries_only": len(entry_keys - result_keys),
        "results_only": len(result_keys - entry_keys),
        f"dropped_field_lt_{MIN_ENTRIES_PER_RACE}": len(shared - enough_entries),
        "dropped_no_winner": len(enough_entries - with_winner),
        "trainable_races": len(with_winner),
        "trainable_by_month": _coverage_by_month(
            [{"race_date": k[1]} for k in with_winner]
        ),
        "sample_dropped_small_field": [list(k) for k in dropped_small_field],
        "sample_dropped_no_winner": [list(k) for k in dropped_no_winner],
    }


def audit_win_odds(results: list[dict[str, Any]]) -> dict[str, Any]:
    """`race_results.win_odds` 를 사전 시장 피처로 쓸 수 있는지 판정한다.

    단승 배당금은 1착에게만 지급되므로, KRA 응답에 따라 1착 행만 값이
    채워질 수 있다. 그 경우 값의 존재 자체가 정답이므로 학습에 쓰면 누출이다.
    """
    winner_filled = 0
    winner_total = 0
    loser_filled = 0
    loser_total = 0

    for row in results:
        rank = _safe_int(row.get("rank", 0))
        if rank <= 0:
            continue
        filled = _safe_float(row.get("win_odds", 0.0)) > 0
        if rank == 1:
            winner_total += 1
            winner_filled += int(filled)
        else:
            loser_total += 1
            loser_filled += int(filled)

    winner_rate = (winner_filled / winner_total) if winner_total else 0.0
    loser_rate = (loser_filled / loser_total) if loser_total else 0.0

    # race_results 는 결과 API에서 온 확정값이고 수집시각도 없다. 커버리지가
    # 높아도 경주 전 값임을 증명할 수 없으므로 사전 피처로는 항상 금지한다.
    usable = False
    if loser_rate < 0.05:
        verdict = "사용 금지: 사실상 1착 행에만 배당이 있어 결과 누출입니다."
    elif loser_rate >= 0.80:
        verdict = (
            "사용 금지: 전 출주마 커버리지는 높지만 확정 결과의 배당이며 "
            "경주 전 captured_at 이 없습니다."
        )
    else:
        verdict = "보류: 채움률이 불균일합니다. 원인 파악 전에는 사용하지 마십시오."

    return {
        "winner_rows": winner_total,
        "winner_filled_rate": round(winner_rate, 4),
        "non_winner_rows": loser_total,
        "non_winner_filled_rate": round(loser_rate, 4),
        "usable_as_prerace_feature": usable,
        "verdict": verdict,
    }


def audit_odds_capture(odds: list[dict[str, Any]]) -> dict[str, Any]:
    """`odds.captured_at` 이 경주일보다 앞서는지 확인한다."""
    total = 0
    before_race_day = 0
    missing_captured_at = 0

    for row in odds:
        if str(row.get("bet_type", "")).upper() != "WIN":
            continue
        total += 1
        captured = str(row.get("captured_at", ""))
        race_date = str(row.get("race_date", ""))
        if not captured:
            missing_captured_at += 1
            continue
        captured_day = captured[:10].replace("-", "")
        if len(captured_day) == 8 and len(race_date) == 8 and captured_day <= race_date:
            before_race_day += 1

    ratio = (before_race_day / total) if total else 0.0
    return {
        "win_odds_rows": total,
        "captured_on_or_before_race_day": before_race_day,
        "prerace_ratio": round(ratio, 4),
        "missing_captured_at": missing_captured_at,
        "usable_as_prerace_feature": total > 0 and ratio >= 0.80,
    }


def main() -> None:
    args = parse_args()

    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL / SUPABASE_SERVICE_KEY 환경변수가 필요합니다.")

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    races = _fetch_all_rows(client, "races", "meet,race_date,race_no,distance")
    entries = _fetch_all_rows(
        client,
        "race_entries",
        (
            "meet,race_date,race_no,horse_no,rating,weight,horse_weight,"
            "total_prize,recent_prize,total_races"
        ),
    )
    results = _fetch_all_rows(
        client,
        "race_results",
        (
            "meet,race_date,race_no,horse_no,rank,race_time,weight,"
            "horse_weight,win_odds,s1f,g3f,pass_order,distance"
        ),
    )
    odds = _fetch_all_rows(
        client, "odds", "meet,race_date,race_no,bet_type,horse_no1,rate,captured_at"
    )

    if args.meet:
        races = [r for r in races if str(r.get("meet", "")) == args.meet]
        entries = [r for r in entries if str(r.get("meet", "")) == args.meet]
        results = [r for r in results if str(r.get("meet", "")) == args.meet]
        odds = [r for r in odds if str(r.get("meet", "")) == args.meet]

    date_filter = {"since": args.since, "until": args.until, "on": None}
    races = _filter_by_race_date(races, **date_filter)
    entries = _filter_by_race_date(entries, **date_filter)
    results = _filter_by_race_date(results, **date_filter)
    odds = _filter_by_race_date(odds, **date_filter)

    synthetic_keys = synthetic_race_keys(results)
    integrity = race_integrity_issues(entries, results)
    clean_results = [
        row
        for row in results
        if (
            str(row.get("meet", "")),
            str(row.get("race_date", "")),
            _safe_int(row.get("race_no", 0)),
        )
        not in synthetic_keys
    ]
    eligible_results = [
        row
        for row in clean_results
        if (
            str(row.get("meet", "")),
            str(row.get("race_date", "")),
            _safe_int(row.get("race_no", 0)),
        )
        not in integrity
    ]
    report = {
        "generated_at": datetime.now().isoformat(),
        "filters": {"meet": args.meet, "since": args.since, "until": args.until},
        "row_counts": {
            "races": len(races),
            "race_entries": len(entries),
            "race_results": len(results),
            "odds": len(odds),
        },
        "distinct_races": {
            "races": len(_distinct_races(races)),
            "race_entries": len(_distinct_races(entries)),
            "race_results": len(_distinct_races(results)),
        },
        "coverage_by_month": {
            "races": _coverage_by_month(races),
            "race_results": _coverage_by_month(results),
        },
        "data_quality": {
            "synthetic_suspect_races": len(synthetic_keys),
            "synthetic_suspect_rows": len(results) - len(clean_results),
            "sample_synthetic_races": [list(k) for k in sorted(synthetic_keys)[:10]],
            "integrity_issue_races": len(integrity),
            "integrity_issue_counts": dict(
                sorted(
                    {
                        issue: sum(issue in issues for issues in integrity.values())
                        for issues in integrity.values()
                        for issue in issues
                    }.items()
                )
            ),
            "sample_integrity_issues": [
                {"race": list(key), "issues": list(issues)}
                for key, issues in sorted(integrity.items())[:10]
            ],
            "entry_missing_rates": column_missing_rates(
                entries,
                (
                    "rating",
                    "weight",
                    "horse_weight",
                    "total_prize",
                    "recent_prize",
                    "total_races",
                ),
            ),
            "result_missing_rates": column_missing_rates(
                clean_results,
                (
                    "rank",
                    "race_time",
                    "weight",
                    "horse_weight",
                    "s1f",
                    "g3f",
                    "pass_order",
                    "distance",
                ),
            ),
        },
        "trainable": audit_trainable_races(entries, eligible_results),
        "win_odds_leakage": audit_win_odds(results),
        "odds_capture": audit_odds_capture(odds),
    }

    trainable = report["trainable"]["trainable_races"]
    print("=" * 60)
    print(f"행 수: {report['row_counts']}")
    print(f"경주 수(entries/results/both): "
          f"{report['trainable']['races_with_entries']} / "
          f"{report['trainable']['races_with_results']} / "
          f"{report['trainable']['races_with_both']}")
    print(f"학습 가능 경주: {trainable}건 (목표 3000건)")
    if trainable < 3000:
        print("  → 표본 부족. historical-backfill 워크플로로 과거 데이터를 확대하십시오.")
    print(
        f"합성 의심 격리: {report['data_quality']['synthetic_suspect_races']}경주 / "
        f"{report['data_quality']['synthetic_suspect_rows']}행"
    )
    print(
        f"정합성 문제: {report['data_quality']['integrity_issue_races']}경주 "
        f"{report['data_quality']['integrity_issue_counts']}"
    )
    print("-" * 60)
    print(f"win_odds 감사: {report['win_odds_leakage']['verdict']}")
    print(f"  1착 채움률={report['win_odds_leakage']['winner_filled_rate']:.2%} "
          f"비1착 채움률={report['win_odds_leakage']['non_winner_filled_rate']:.2%}")
    print(f"odds.captured_at 사전 비율: {report['odds_capture']['prerace_ratio']:.2%} "
          f"(사전 피처 사용 가능={report['odds_capture']['usable_as_prerace_feature']})")
    print("-" * 60)
    print("월별 결과 커버리지:")
    for month, count in report["coverage_by_month"]["race_results"].items():
        print(f"  {month}: {count}행")
    print("=" * 60)

    if args.json_path:
        with open(args.json_path, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print(f"[DONE] 감사 결과 저장: {args.json_path}")


if __name__ == "__main__":
    main()
