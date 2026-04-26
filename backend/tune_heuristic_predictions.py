"""로컬 휴리스틱 예측 가중치 자동 튜닝 스크립트.

실제 경주 결과(race_results)와 출마표(race_entries)를 대조하여
Top1/Top3 적중률 + 확률 보정(Brier score) 기준으로 가중치를 탐색합니다.

사용 예시:
  python backend/tune_heuristic_predictions.py --meet 1 --since 20250101 --trials 180
  python backend/tune_heuristic_predictions.py --sync-predictions --model-version heuristic-place-1.1
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from supabase import create_client

from config import SUPABASE_SERVICE_KEY, SUPABASE_URL


@dataclass
class HeuristicParams:
    w_rating: float
    w_perf: float
    w_class_form: float
    w_pace: float
    w_condition: float
    w_market: float
    rating_pow: float
    prior_weight: float
    temp_scale: float
    reliability_penalty: float

    def to_dict(self) -> dict[str, float]:
        return {
            "w_rating": round(self.w_rating, 6),
            "w_perf": round(self.w_perf, 6),
            "w_class_form": round(self.w_class_form, 6),
            "w_pace": round(self.w_pace, 6),
            "w_condition": round(self.w_condition, 6),
            "w_market": round(self.w_market, 6),
            "rating_pow": round(self.rating_pow, 6),
            "prior_weight": round(self.prior_weight, 6),
            "temp_scale": round(self.temp_scale, 6),
            "reliability_penalty": round(self.reliability_penalty, 6),
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="휴리스틱 예측 자동 튜닝")
    parser.add_argument("--meet", default=None, help="경마장 코드(1/2/3), 미지정 시 전체")
    parser.add_argument("--since", default=None, help="조회 시작일(YYYYMMDD, inclusive)")
    parser.add_argument(
        "--until", default=None, help="조회 종료일(YYYYMMDD, inclusive). on 미지정일 때만 적용"
    )
    parser.add_argument(
        "--on",
        dest="on_date",
        default=None,
        help="특정 시행일만(YYYYMMDD). 지정 시 since/until 대신 해당 일만 사용",
    )
    parser.add_argument("--max-races", type=int, default=800, help="튜닝에 사용할 최대 경주 수")
    parser.add_argument("--trials", type=int, default=160, help="랜덤 탐색 횟수")
    parser.add_argument("--seed", type=int, default=42, help="난수 시드")
    parser.add_argument(
        "--sync-predictions",
        action="store_true",
        help="최적 가중치로 predictions 테이블에 업서트",
    )
    parser.add_argument(
        "--model-version",
        default="heuristic-place-1.1",
        help="동기화 시 사용할 model_version",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="튜닝 JSON 저장 경로(기본: backend/models/heuristic_tuned_params.json)",
    )
    return parser.parse_args()


def _safe_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _normalize(v: float, min_v: float, max_v: float) -> float:
    if max_v <= min_v:
        return 0.5
    return max(0.0, min(1.0, (v - min_v) / (max_v - min_v)))


def _sample_reliability(total_races: int) -> float:
    if total_races <= 0:
        return 0.0
    return max(0.0, min(1.0, total_races / 12.0))


def _running_styles(entries: list[dict[str, Any]]) -> dict[int, str]:
    result: dict[int, str] = {}
    for e in entries:
        horse_no = _safe_int(e.get("horse_no", 0))
        rating = _safe_float(e.get("rating", 0))
        win_cnt = _safe_int(e.get("win_count", 0))
        total_races = _safe_int(e.get("total_races", 0))
        win_rate = (win_cnt / total_races * 100.0) if total_races > 0 else 0.0

        if rating >= 85 and win_rate >= 20:
            result[horse_no] = "선행"
        elif rating >= 70 and win_rate >= 10:
            result[horse_no] = "선입"
        elif rating < 50 or (total_races >= 5 and win_rate < 5):
            result[horse_no] = "추입"
        else:
            result[horse_no] = "중단"
    return result


def _pace_score(style: str, pace_pressure: bool, front_count: int) -> float:
    if pace_pressure and style in ("추입", "중단"):
        return 1.0
    if not pace_pressure and style in ("선행", "선입"):
        return 0.92
    if front_count <= 2 and style == "선행":
        return 0.84
    if front_count >= 5 and style == "추입":
        return 0.84
    return 0.55


def _condition_score(entry: dict[str, Any], min_hw: float, max_hw: float) -> float:
    age = _safe_int(entry.get("age", 0))
    burden = _safe_float(entry.get("weight", 0))
    horse_weight = _safe_float(entry.get("horse_weight", 0))
    total_races = _safe_int(entry.get("total_races", 0))

    age_score = 1.0 if 3 <= age <= 5 else 0.65 if age == 6 else 0.45
    burden_score = 0.95 if 52 <= burden <= 56 else 0.62 if 50 <= burden <= 57 else 0.35
    body_norm = _normalize(horse_weight, min_hw, max_hw)
    body_mid = max(0.0, 1.0 - abs(body_norm - 0.5) * 2.0)
    exp_bonus = 0.18 if total_races >= 5 else 0.0

    return min(1.0, (age_score * 0.40) + (burden_score * 0.33) + (body_mid * 0.27) + exp_bonus)


def _temperature(horse_count: int, spread: float, temp_scale: float) -> float:
    base = 6.8 if horse_count <= 6 else 8.2 if horse_count <= 10 else 9.3
    spread_factor = 1.15 if spread <= 8 else 1.0 if spread <= 14 else 0.88
    return max(5.5, min(11.0, base * spread_factor * temp_scale))


def _place_probability(win_prob: float, horse_count: int, rank: int) -> float:
    field_boost = 8.0 if horse_count >= 10 else 5.0
    rank_boost = (
        9.0
        if rank == 1
        else 7.0
        if rank == 2
        else 6.0
        if rank == 3
        else 3.0
        if rank <= 5
        else 1.0
    )
    place_prob = (win_prob * 1.65) + field_boost + rank_boost
    return max(win_prob + 4.0, min(92.0, place_prob))


def _market_implied_by_win_odds(
    win_rates_by_horse: dict[int, float],
    entry_horse_nos: set[int],
) -> dict[int, float]:
    if not win_rates_by_horse:
        return {}

    rates: dict[int, float] = {}
    for h, r in win_rates_by_horse.items():
        if h <= 0 or r <= 0:
            continue
        if h not in entry_horse_nos:
            continue
        prev = rates.get(h)
        if prev is None or r < prev:
            rates[h] = r
    if not rates:
        return {}

    inv_sum = sum(1.0 / r for r in rates.values())
    if inv_sum <= 0:
        return {}
    return {h: (1.0 / r) / inv_sum for h, r in rates.items()}


def _fetch_all_rows(client, table: str, columns: str, batch_size: int = 1000) -> list[dict]:
    rows: list[dict] = []
    offset = 0
    while True:
        res = (
            client.table(table)
            .select(columns)
            .range(offset, offset + batch_size - 1)
            .execute()
        )
        chunk = res.data or []
        if not chunk:
            break
        rows.extend(chunk)
        if len(chunk) < batch_size:
            break
        offset += batch_size
    return rows


def _filter_by_race_date(
    rows: list[dict[str, Any]],
    *,
    since: str | None,
    until: str | None,
    on: str | None,
) -> list[dict[str, Any]]:
    if on and len(str(on)) == 8:
        o = str(on)
        return [r for r in rows if str(r.get("race_date", "")) == o]
    out = rows
    if since:
        out = [r for r in out if str(r.get("race_date", "")) >= since]
    if until:
        out = [r for r in out if str(r.get("race_date", "")) <= until]
    return out


def _build_race_dataset(
    client,
    meet: str | None,
    since: str | None,
    max_races: int,
    until: str | None = None,
    on: str | None = None,
) -> list[dict[str, Any]]:
    all_results = _fetch_all_rows(
        client,
        "race_results",
        "meet,race_date,race_no,horse_no,rank",
    )
    all_entries = _fetch_all_rows(
        client,
        "race_entries",
        (
            "meet,race_date,race_no,horse_no,horse_name,age,weight,rating,"
            "total_prize,recent_prize,win_count,place_count,total_races,horse_weight"
        ),
    )
    all_races = _fetch_all_rows(client, "races", "meet,race_date,race_no,distance")

    if meet:
        all_results = [r for r in all_results if str(r.get("meet", "")) == meet]
        all_entries = [e for e in all_entries if str(e.get("meet", "")) == meet]
        all_races = [r for r in all_races if str(r.get("meet", "")) == meet]
    all_results = _filter_by_race_date(
        all_results, since=since, until=until, on=on
    )
    all_entries = _filter_by_race_date(
        all_entries, since=since, until=until, on=on
    )
    all_races = _filter_by_race_date(all_races, since=since, until=until, on=on)

    results_by_race: dict[tuple[str, str, int], list[dict[str, Any]]] = {}
    for row in all_results:
        race_no = _safe_int(row.get("race_no", 0))
        if race_no <= 0:
            continue
        key = (str(row.get("meet", "")), str(row.get("race_date", "")), race_no)
        results_by_race.setdefault(key, []).append(row)

    entries_by_race: dict[tuple[str, str, int], list[dict[str, Any]]] = {}
    for row in all_entries:
        race_no = _safe_int(row.get("race_no", 0))
        horse_no = _safe_int(row.get("horse_no", 0))
        if race_no <= 0 or horse_no <= 0:
            continue
        key = (str(row.get("meet", "")), str(row.get("race_date", "")), race_no)
        entries_by_race.setdefault(key, []).append(row)

    distance_by_race: dict[tuple[str, str, int], int] = {}
    for row in all_races:
        race_no = _safe_int(row.get("race_no", 0))
        if race_no <= 0:
            continue
        key = (str(row.get("meet", "")), str(row.get("race_date", "")), race_no)
        distance_by_race[key] = _safe_int(row.get("distance", 0), 1400)

    all_odds = _fetch_all_rows(
        client,
        "odds",
        "meet,race_date,race_no,bet_type,horse_no1,rate",
    )
    if meet:
        all_odds = [o for o in all_odds if str(o.get("meet", "")) == meet]
    all_odds = _filter_by_race_date(
        all_odds, since=since, until=until, on=on
    )

    win_odds_by_race: dict[tuple[str, str, int], dict[int, float]] = {}
    for row in all_odds:
        if str(row.get("bet_type", "")).upper() != "WIN":
            continue
        race_no = _safe_int(row.get("race_no", 0))
        if race_no <= 0:
            continue
        k = (str(row.get("meet", "")), str(row.get("race_date", "")), race_no)
        horse_no = _safe_int(row.get("horse_no1", 0))
        rate = _safe_float(row.get("rate", 0.0), 0.0)
        if horse_no <= 0 or rate <= 0:
            continue
        m = win_odds_by_race.setdefault(k, {})
        prev = m.get(horse_no)
        if prev is None or rate < prev:
            m[horse_no] = rate

    race_keys = sorted(
        set(results_by_race.keys()) & set(entries_by_race.keys()),
        key=lambda x: (x[1], x[2]),
        reverse=True,
    )

    samples: list[dict[str, Any]] = []
    for key in race_keys:
        results = results_by_race[key]
        entries = entries_by_race[key]
        if len(entries) < 5:
            continue

        winner_rows = [r for r in results if _safe_int(r.get("rank", 0)) == 1]
        if not winner_rows:
            continue

        actual_top3 = {
            _safe_int(r.get("horse_no", 0))
            for r in results
            if 1 <= _safe_int(r.get("rank", 0)) <= 3
        }
        winner_no = _safe_int(winner_rows[0].get("horse_no", 0))
        if winner_no <= 0:
            continue

        samples.append(
            {
                "key": key,
                "entries": entries,
                "winner_no": winner_no,
                "actual_top3": actual_top3,
                "distance": distance_by_race.get(key, 1400),
                "win_odds": win_odds_by_race.get(key, {}),
            }
        )
        if max_races > 0 and len(samples) >= max_races:
            break

    return samples


def _race_probabilities(
    entries: list[dict[str, Any]],
    params: HeuristicParams,
    win_odds: dict[int, float] | None = None,
) -> list[dict[str, Any]]:
    ratings = [_safe_float(e.get("rating", 0)) for e in entries]
    total_prizes = [_safe_float(e.get("total_prize", 0)) for e in entries]
    recent_prizes = [_safe_float(e.get("recent_prize", 0)) for e in entries]
    horse_weights = [_safe_float(e.get("horse_weight", 0)) for e in entries]

    min_rating, max_rating = min(ratings), max(ratings)
    min_prize, max_prize = min(total_prizes), max(total_prizes)
    min_recent, max_recent = min(recent_prizes), max(recent_prizes)
    min_hw, max_hw = min(horse_weights), max(horse_weights)

    win_rates = []
    place_rates = []
    for e in entries:
        total_races = _safe_int(e.get("total_races", 0))
        win_count = _safe_int(e.get("win_count", 0))
        place_count = _safe_int(e.get("place_count", 0))
        wr = (win_count / total_races * 100.0) if total_races > 0 else 0.0
        pr = ((win_count + place_count) / total_races * 100.0) if total_races > 0 else 0.0
        win_rates.append(wr)
        place_rates.append(pr)

    avg_wr = sum(win_rates) / len(win_rates)
    avg_pr = sum(place_rates) / len(place_rates)

    styles = _running_styles(entries)
    front_count = sum(1 for s in styles.values() if s in ("선행", "선입"))
    pace_pressure = front_count >= 4

    raw_scores: list[float] = []
    horse_nos: list[int] = []
    entry_horse_nos = {_safe_int(e.get("horse_no", 0)) for e in entries if _safe_int(e.get("horse_no", 0)) > 0}
    market_by = _market_implied_by_win_odds(win_odds or {}, entry_horse_nos)
    field = len(entries)
    coverage = (len(market_by) / field) if field > 0 else 0.0
    market_w = 0.0
    if coverage >= 0.35 and params.w_market > 0.0 and market_by:
        market_w = max(0.0, min(1.0, params.w_market * coverage))

    for idx, e in enumerate(entries):
        horse_no = _safe_int(e.get("horse_no", 0))
        horse_nos.append(horse_no)
        style = styles.get(horse_no, "중단")

        total_races = _safe_int(e.get("total_races", 0))
        win_count = _safe_int(e.get("win_count", 0))
        place_count = _safe_int(e.get("place_count", 0))
        wr = win_rates[idx]
        pr = place_rates[idx]

        rating_comp = _normalize(_safe_float(e.get("rating", 0)), min_rating, max_rating)
        rating_comp = pow(rating_comp, params.rating_pow)

        samples = float(total_races)
        smooth_wr = ((wr * samples) + (avg_wr * params.prior_weight)) / (samples + params.prior_weight)
        smooth_pr = ((pr * samples) + (avg_pr * params.prior_weight)) / (samples + params.prior_weight)
        consistency = max(0.0, smooth_pr - smooth_wr)
        perf_comp = (
            (_normalize(smooth_wr, 0, 40) * 0.48)
            + (_normalize(smooth_pr, 0, 75) * 0.42)
            + (_normalize(consistency, 0, 35) * 0.10)
        )

        prize_log = math.log(max(_safe_float(e.get("total_prize", 0)), 0.0) + 1.0)
        recent_log = math.log(max(_safe_float(e.get("recent_prize", 0)), 0.0) + 1.0)
        class_comp = (
            _normalize(
                prize_log,
                math.log(max(min_prize, 0.0) + 1),
                math.log(max(max_prize, 0.0) + 1),
            )
            * 0.45
            + _normalize(
                recent_log,
                math.log(max(min_recent, 0.0) + 1),
                math.log(max(max_recent, 0.0) + 1),
            )
            * 0.55
        )

        pace_comp = _pace_score(style=style, pace_pressure=pace_pressure, front_count=front_count)
        condition_comp = _condition_score(e, min_hw, max_hw)

        s = 1.0 - params.w_market
        base_score = s * (
            params.w_rating * rating_comp
            + params.w_perf * perf_comp
            + params.w_class_form * class_comp
            + params.w_pace * pace_comp
            + params.w_condition * condition_comp
        )

        market_comp = market_by.get(horse_no, 0.5)
        if market_w > 0.0:
            blended = base_score + (market_comp * market_w)
        else:
            blended = base_score

        reliability = _sample_reliability(total_races)
        reliability_factor = 1.0 - (params.reliability_penalty * (1.0 - reliability))
        raw_scores.append(max(1e-6, blended * reliability_factor * 100.0))

    max_raw = max(raw_scores)
    min_raw = min(raw_scores)
    spread = max_raw - min_raw
    temp = _temperature(len(entries), spread, params.temp_scale)
    exps = [math.exp((s - max_raw) / temp) for s in raw_scores]
    total_exp = sum(exps)
    probs = [(v / total_exp) * 100.0 for v in exps]

    ranked_idx = sorted(range(len(entries)), key=lambda i: probs[i], reverse=True)
    rank_by_idx = {idx: rank + 1 for rank, idx in enumerate(ranked_idx)}

    rows: list[dict[str, Any]] = []
    for i, e in enumerate(entries):
        horse_no = _safe_int(e.get("horse_no", 0))
        win_prob = probs[i]
        rank = rank_by_idx[i]
        place_prob = _place_probability(win_prob, len(entries), rank)
        rows.append(
            {
                "horse_no": horse_no,
                "horse_name": str(e.get("horse_name", "")),
                "win_probability": win_prob,
                "place_probability": place_prob,
                "rank": rank,
            }
        )
    rows.sort(
        key=lambda p: (
            -p["win_probability"],
            -p["place_probability"],
            p["horse_no"],
        )
    )
    for rank, row in enumerate(rows, start=1):
        row["rank"] = rank
    return rows


def _evaluate(samples: list[dict[str, Any]], params: HeuristicParams) -> dict[str, float]:
    if not samples:
        return {
            "objective": 0.0,
            "top1_acc": 0.0,
            "top3_match": 0.0,
            "top3_winner": 0.0,
            "brier": 1.0,
            "races": 0,
        }

    top1_hits = 0
    top3_match_sum = 0.0
    top3_winner_hits = 0
    brier_sum = 0.0
    total_horses = 0

    for race in samples:
        preds = _race_probabilities(race["entries"], params, win_odds=race.get("win_odds", {}) or None)
        preds.sort(
            key=lambda p: (
                -p["win_probability"],
                -p["place_probability"],
                p["horse_no"],
            )
        )

        winner_no = race["winner_no"]
        actual_top3 = race["actual_top3"] or set()
        pred_top3 = {p["horse_no"] for p in preds[:3]}

        if preds and preds[0]["horse_no"] == winner_no:
            top1_hits += 1
        if winner_no in pred_top3:
            top3_winner_hits += 1
        if actual_top3:
            top3_match_sum += len(pred_top3 & actual_top3) / min(3, len(actual_top3))

        for p in preds:
            y = 1.0 if p["horse_no"] in actual_top3 else 0.0
            pr = p["place_probability"] / 100.0
            brier_sum += (pr - y) ** 2
        total_horses += len(preds)

    race_count = len(samples)
    top1_acc = top1_hits / race_count
    top3_match = top3_match_sum / race_count
    top3_winner = top3_winner_hits / race_count
    brier = brier_sum / max(1, total_horses)

    # 앱의 목표와 동일하게 입상권 포함률을 최우선으로 평가합니다.
    # 1위(단승) 적중을 최우선 — 입상권과의 균형
    objective = (
        (top1_acc * 0.50)
        + (top3_match * 0.30)
        + (top3_winner * 0.12)
        + ((1.0 - brier) * 0.08)
    )

    return {
        "objective": objective,
        "top1_acc": top1_acc,
        "top3_match": top3_match,
        "top3_winner": top3_winner,
        "brier": brier,
        "races": race_count,
    }


def _normalize_weights(params: HeuristicParams) -> HeuristicParams:
    total = (
        params.w_rating
        + params.w_perf
        + params.w_class_form
        + params.w_pace
        + params.w_condition
        + params.w_market
    )
    if total <= 0:
        total = 1.0
    return HeuristicParams(
        w_rating=params.w_rating / total,
        w_perf=params.w_perf / total,
        w_class_form=params.w_class_form / total,
        w_pace=params.w_pace / total,
        w_condition=params.w_condition / total,
        w_market=params.w_market / total,
        rating_pow=params.rating_pow,
        prior_weight=params.prior_weight,
        temp_scale=params.temp_scale,
        reliability_penalty=params.reliability_penalty,
    )


def heuristic_params_from_dict(
    d: dict[str, Any], *, default_w_market: float = 0.0
) -> HeuristicParams:
    """`heuristic_tuned_params.json`의 best_params 등에서 HeuristicParams 복원."""
    return _normalize_weights(
        HeuristicParams(
            w_rating=_safe_float(d.get("w_rating", 0.0), 0.0),
            w_perf=_safe_float(d.get("w_perf", 0.0), 0.0),
            w_class_form=_safe_float(d.get("w_class_form", 0.0), 0.0),
            w_pace=_safe_float(d.get("w_pace", 0.0), 0.0),
            w_condition=_safe_float(d.get("w_condition", 0.0), 0.0),
            w_market=_safe_float(d.get("w_market", default_w_market), default_w_market),
            rating_pow=_safe_float(d.get("rating_pow", 2.0), 2.0),
            prior_weight=_safe_float(d.get("prior_weight", 7.0), 7.0),
            temp_scale=_safe_float(d.get("temp_scale", 1.0), 1.0),
            reliability_penalty=_safe_float(
                d.get("reliability_penalty", 0.15), 0.15
            ),
        )
    )


def _mutate(base: HeuristicParams, rng: random.Random) -> HeuristicParams:
    def n(value: float, scale: float, lo: float, hi: float) -> float:
        return max(lo, min(hi, value + rng.uniform(-scale, scale)))

    mutated = HeuristicParams(
        w_rating=n(base.w_rating, 0.10, 0.05, 0.65),
        w_perf=n(base.w_perf, 0.10, 0.05, 0.65),
        w_class_form=n(base.w_class_form, 0.08, 0.03, 0.50),
        w_pace=n(base.w_pace, 0.06, 0.01, 0.35),
        w_condition=n(base.w_condition, 0.06, 0.01, 0.35),
        w_market=n(base.w_market, 0.04, 0.0, 0.30),
        rating_pow=n(base.rating_pow, 0.25, 0.8, 2.2),
        prior_weight=n(base.prior_weight, 2.5, 2.0, 18.0),
        temp_scale=n(base.temp_scale, 0.20, 0.75, 1.35),
        reliability_penalty=n(base.reliability_penalty, 0.07, 0.02, 0.35),
    )
    return _normalize_weights(mutated)


def _sync_predictions(
    client,
    samples: list[dict[str, Any]],
    params: HeuristicParams,
    model_version: str,
) -> int:
    rows: list[dict[str, Any]] = []
    for race in samples:
        meet, race_date, race_no = race["key"]
        preds = _race_probabilities(race["entries"], params, win_odds=race.get("win_odds", {}) or None)
        preds.sort(
            key=lambda p: (
                -p["win_probability"],
                -p["place_probability"],
                p["horse_no"],
            )
        )
        for p in preds:
            tags = []
            if p["rank"] == 1:
                tags.append("입상강력")
            elif p["rank"] <= 3:
                tags.append("입상유력")
            if p["place_probability"] >= 45:
                tags.append("고입상")

            rows.append(
                {
                    "meet": meet,
                    "race_date": race_date,
                    "race_no": race_no,
                    "horse_no": p["horse_no"],
                    "horse_name": p["horse_name"],
                    "win_probability": round(p["win_probability"], 2),
                    "place_probability": round(p["place_probability"], 2),
                    "tags": tags,
                    "feature_importance": params.to_dict(),
                    "model_version": model_version,
                }
            )

    synced = 0
    for i in range(0, len(rows), 500):
        batch = rows[i : i + 500]
        res = client.table("predictions").upsert(
            batch,
            on_conflict="meet,race_date,race_no,horse_no,model_version",
        ).execute()
        synced += len(res.data) if res.data else 0
    return synced


def main() -> None:
    args = parse_args()

    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL / SUPABASE_SERVICE_KEY 환경변수가 필요합니다.")

    rng = random.Random(args.seed)
    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    samples = _build_race_dataset(
        client=client,
        meet=args.meet,
        since=args.since,
        max_races=args.max_races,
        until=args.until,
        on=args.on_date,
    )
    if not samples:
        print("튜닝 가능한 경주 데이터가 없습니다.")
        return

    print(f"[INFO] 튜닝 대상 경주 수: {len(samples)}")

    baseline = _normalize_weights(
        HeuristicParams(
            w_rating=0.324359,
            w_perf=0.371729,
            w_class_form=0.020350,
            w_pace=0.005776,
            w_condition=0.277786,
            w_market=0.0,
            rating_pow=2.614967,
            prior_weight=7.375545,
            temp_scale=1.595725,
            reliability_penalty=0.174242,
        )
    )
    best_params = baseline
    best_metrics = _evaluate(samples, baseline)

    print(
        "[BASE] objective={:.4f} top1={:.3f} top3_match={:.3f} top3_winner={:.3f} brier={:.4f}".format(
            best_metrics["objective"],
            best_metrics["top1_acc"],
            best_metrics["top3_match"],
            best_metrics["top3_winner"],
            best_metrics["brier"],
        )
    )

    for trial in range(1, args.trials + 1):
        candidate = _mutate(best_params, rng) if trial > 1 else baseline
        metrics = _evaluate(samples, candidate)
        if metrics["objective"] > best_metrics["objective"]:
            best_params = candidate
            best_metrics = metrics
            print(
                "[BEST {:03d}] objective={:.4f} top1={:.3f} top3_match={:.3f} top3_winner={:.3f} brier={:.4f}".format(
                    trial,
                    metrics["objective"],
                    metrics["top1_acc"],
                    metrics["top3_match"],
                    metrics["top3_winner"],
                    metrics["brier"],
                )
            )

    result_payload = {
        "generated_at": datetime.now().isoformat(),
        "filters": {
            "meet": args.meet,
            "since": args.since,
            "until": args.until,
            "on": args.on_date,
            "max_races": args.max_races,
            "trials": args.trials,
            "seed": args.seed,
        },
        "metrics": {
            k: round(v, 6) if isinstance(v, float) else v
            for k, v in best_metrics.items()
        },
        "objective_weights": {
            "top1_acc": 0.50,
            "top3_match": 0.30,
            "top3_winner": 0.12,
            "brier": 0.08,
        },
        "best_params": best_params.to_dict(),
    }

    output_path = args.output or os.path.join(
        os.path.dirname(__file__),
        "models",
        "heuristic_tuned_params.json",
    )
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result_payload, f, ensure_ascii=False, indent=2)
    print(f"[DONE] 튜닝 결과 저장: {output_path}")

    if args.sync_predictions:
        synced = _sync_predictions(
            client=client,
            samples=samples,
            params=best_params,
            model_version=args.model_version,
        )
        print(
            f"[SYNC] model_version={args.model_version} predictions 업서트 완료: {synced}건"
        )


if __name__ == "__main__":
    main()
