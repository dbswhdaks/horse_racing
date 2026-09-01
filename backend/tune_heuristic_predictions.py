"""로컬 휴리스틱 예측 가중치 자동 튜닝 스크립트.

실제 경주 결과(race_results)와 출마표(race_entries)를 대조하여
입상권(Top3) 포함률을 최우선 목표로 가중치를 탐색합니다.

탐색은 시간순 walk-forward 교차검증의 평균 목적함수로 이뤄지고,
마지막 구간은 홀드아웃으로 남겨 탐색에 전혀 쓰지 않습니다.

사용 예시:
  python backend/tune_heuristic_predictions.py --meet 1 --since 20250101 --trials 180
  python backend/tune_heuristic_predictions.py --sync-predictions
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
from entry_features import (
    FITNESS_FEATURE_KEY,
    JOCKEY_FEATURE_KEY,
    NEUTRAL_SCORE,
    RECENT_FORM_FEATURE_KEY,
    AsOfFeatureIndex,
)
from prediction_constants import (
    MAX_TRAINING_RACES,
    MIN_ENTRIES_PER_RACE,
    MODEL_VERSION,
    OBJECTIVE_WEIGHTS,
    WALK_FORWARD_FOLDS,
)

# 홀드아웃으로 떼어 두는 최신 구간 비율. 탐색에 전혀 사용하지 않습니다.
HOLDOUT_RATIO = 0.15

# 입상권으로 인정하는 착순 범위.
PLACE_SLOTS = 3


@dataclass
class HeuristicParams:
    w_rating: float
    w_perf: float
    w_class_form: float
    w_pace: float
    w_condition: float
    w_market: float
    w_jockey: float
    w_recent_form: float
    w_fitness: float
    rating_pow: float
    prior_weight: float
    temp_scale: float
    place_temp_scale: float
    reliability_penalty: float

    def to_dict(self) -> dict[str, float]:
        return {
            "w_rating": round(self.w_rating, 6),
            "w_perf": round(self.w_perf, 6),
            "w_class_form": round(self.w_class_form, 6),
            "w_pace": round(self.w_pace, 6),
            "w_condition": round(self.w_condition, 6),
            "w_market": round(self.w_market, 6),
            "w_jockey": round(self.w_jockey, 6),
            "w_recent_form": round(self.w_recent_form, 6),
            "w_fitness": round(self.w_fitness, 6),
            "rating_pow": round(self.rating_pow, 6),
            "prior_weight": round(self.prior_weight, 6),
            "temp_scale": round(self.temp_scale, 6),
            "place_temp_scale": round(self.place_temp_scale, 6),
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
    parser.add_argument(
        "--max-races",
        type=int,
        default=MAX_TRAINING_RACES,
        help="튜닝에 사용할 최대 경주 수",
    )
    parser.add_argument("--trials", type=int, default=160, help="랜덤 탐색 횟수")
    parser.add_argument("--seed", type=int, default=42, help="난수 시드")
    parser.add_argument(
        "--folds",
        type=int,
        default=WALK_FORWARD_FOLDS,
        help="시간순 walk-forward 검증 블록 수",
    )
    parser.add_argument(
        "--sync-predictions",
        action="store_true",
        help="최적 가중치로 predictions 테이블에 업서트",
    )
    parser.add_argument(
        "--model-version",
        default=MODEL_VERSION,
        help="동기화 시 사용할 model_version",
    )
    parser.add_argument(
        "--include-market-odds",
        action="store_true",
        help="수집 시점이 보장된 사전 배당만 학습에 포함(기본값: 누출 방지를 위해 제외)",
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


def _harville_place_probs(
    win_probs: list[float], slots: int = PLACE_SLOTS
) -> list[float]:
    """Harville 공식으로 단승 확률에서 입상(top-`slots`) 확률을 유도한다.

    말 i가 2착일 확률은 "j가 1착이고 남은 풀에서 i가 뽑힐 확률"의 합이며,
    3착도 같은 방식으로 조건부 추출을 한 단계 더 적용한다. 두수가 최대
    16이므로 O(n^2) 항등식으로 정확히 계산한다.

    입력·출력 모두 0~1 스케일이다.
    """
    n = len(win_probs)
    if n == 0:
        return []
    if n <= slots:
        return [1.0] * n

    total = sum(win_probs)
    if total <= 0:
        return [slots / n] * n
    p = [max(v / total, 1e-12) for v in win_probs]

    eps = 1e-9

    # 1착 확률
    probs = list(p)
    if slots <= 1:
        return [min(1.0, max(0.0, v)) for v in probs]

    # 2착 확률: P(i 2착) = p_i * (T - p_i/(1-p_i)),  T = sum_j p_j/(1-p_j)
    ratio = [p_j / max(1.0 - p_j, eps) for p_j in p]
    t_sum = sum(ratio)
    for i in range(n):
        probs[i] += p[i] * (t_sum - ratio[i])
    if slots <= 2:
        return [min(1.0, max(0.0, v)) for v in probs]

    # 3착 확률: 순서쌍 (j, k) 를 미리 합산해 i 루프를 O(n)으로 줄인다.
    #   c[j][k] = p_j * (p_k / (1 - p_j)) / (1 - p_j - p_k)
    #   P(i 3착) = p_i * (S - rowsum_i - colsum_i)
    pair_total = 0.0
    row_sum = [0.0] * n
    col_sum = [0.0] * n
    for j in range(n):
        first = p[j]
        rest = max(1.0 - first, eps)
        for k in range(n):
            if k == j:
                continue
            denom = max(1.0 - first - p[k], eps)
            c = first * (p[k] / rest) / denom
            pair_total += c
            row_sum[j] += c
            col_sum[k] += c

    for i in range(n):
        probs[i] += p[i] * (pair_total - row_sum[i] - col_sum[i])

    return [min(1.0, max(0.0, v)) for v in probs]


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


def _is_prerace_capture(captured_at: Any, race_date: str) -> bool:
    """배당 수집 시각이 경주일 당일 이하인지 확인한다.

    `captured_at` 이 비어 있으면 사후 확정 배당일 수 있으므로 거짓으로 본다.
    """
    text = str(captured_at or "").strip()
    if len(text) < 10 or len(race_date) != 8:
        return False
    captured_day = text[:10].replace("-", "")
    return len(captured_day) == 8 and captured_day <= race_date


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
    include_market_odds: bool = False,
    include_unfinished: bool = False,
) -> list[dict[str, Any]]:
    """튜닝·동기화용 경주 표본을 만든다.

    기본값은 결과가 확정된 경주만 담는다(평가에 정답이 필요하기 때문).
    `include_unfinished` 를 켜면 아직 결과가 없는 앞으로의 경주도 포함하며,
    그런 표본은 `winner_no=0` 이라 평가에서 자동으로 제외된다.
    """
    all_results = _fetch_all_rows(
        client,
        "race_results",
        (
            "meet,race_date,race_no,horse_no,horse_name,jockey_name,"
            "rank,horse_weight,distance"
        ),
    )
    all_entries = _fetch_all_rows(
        client,
        "race_entries",
        (
            "meet,race_date,race_no,horse_no,horse_name,jockey_name,age,weight,"
            "rating,total_prize,recent_prize,win_count,place_count,total_races,"
            "horse_weight"
        ),
    )
    all_races = _fetch_all_rows(client, "races", "meet,race_date,race_no,distance")

    # as-of 인덱스는 날짜 필터 이전의 전체 이력으로 만든다. 구간 앞머리 경주도
    # 과거 성적을 참조할 수 있어야 하기 때문이다.
    feature_index = AsOfFeatureIndex(all_results)

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

    win_odds_by_race: dict[tuple[str, str, int], dict[int, float]] = {}
    if include_market_odds:
        all_odds = _fetch_all_rows(
            client,
            "odds",
            "meet,race_date,race_no,bet_type,horse_no1,rate,captured_at",
        )
        if meet:
            all_odds = [o for o in all_odds if str(o.get("meet", "")) == meet]
        all_odds = _filter_by_race_date(
            all_odds, since=since, until=until, on=on
        )
        skipped_post_race = 0
        for row in all_odds:
            if str(row.get("bet_type", "")).upper() != "WIN":
                continue
            # 경주일 이후에 수집된 배당은 확정 배당일 수 있어 학습에서 제외한다.
            if not _is_prerace_capture(
                row.get("captured_at"), str(row.get("race_date", ""))
            ):
                skipped_post_race += 1
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

        if skipped_post_race:
            print(
                f"[INFO] 경주일 이후 수집된 배당 {skipped_post_race}행을 "
                "누출 방지를 위해 제외했습니다."
            )

    selected_keys = (
        set(entries_by_race.keys())
        if include_unfinished
        else set(results_by_race.keys()) & set(entries_by_race.keys())
    )
    race_keys = sorted(selected_keys, key=lambda x: (x[1], x[2]))
    if max_races > 0:
        race_keys = race_keys[-max_races:]

    samples: list[dict[str, Any]] = []
    for key in race_keys:
        results = results_by_race.get(key, [])
        entries = entries_by_race[key]
        if len(entries) < MIN_ENTRIES_PER_RACE:
            continue

        winner_rows = [r for r in results if _safe_int(r.get("rank", 0)) == 1]
        winner_no = _safe_int(winner_rows[0].get("horse_no", 0)) if winner_rows else 0
        if winner_no <= 0 and not include_unfinished:
            continue

        actual_top3 = {
            _safe_int(r.get("horse_no", 0))
            for r in results
            if 1 <= _safe_int(r.get("rank", 0)) <= PLACE_SLOTS
        }

        distance = distance_by_race.get(key, 1400)
        feature_index.attach_to_entries(
            entries, race_date=key[1], distance=distance
        )

        samples.append(
            {
                "key": key,
                "entries": entries,
                "winner_no": winner_no,
                "actual_top3": actual_top3,
                "distance": distance,
                "win_odds": win_odds_by_race.get(key, {}),
            }
        )
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

        # as-of 시계열 피처. 미리 붙어 있지 않으면 중립값이라 점수에 영향이 없다.
        jockey_comp = _safe_float(e.get(JOCKEY_FEATURE_KEY, NEUTRAL_SCORE), NEUTRAL_SCORE)
        form_comp = _safe_float(e.get(RECENT_FORM_FEATURE_KEY, NEUTRAL_SCORE), NEUTRAL_SCORE)
        fitness_comp = _safe_float(e.get(FITNESS_FEATURE_KEY, NEUTRAL_SCORE), NEUTRAL_SCORE)

        s = 1.0 - market_w
        base_score = s * (
            params.w_rating * rating_comp
            + params.w_perf * perf_comp
            + params.w_class_form * class_comp
            + params.w_pace * pace_comp
            + params.w_condition * condition_comp
            + params.w_jockey * jockey_comp
            + params.w_recent_form * form_comp
            + params.w_fitness * fitness_comp
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

    # 입상 확률은 단승과 다른 온도의 분포에서 Harville 공식으로 유도합니다.
    place_temp = _temperature(len(entries), spread, params.place_temp_scale)
    place_exps = [math.exp((s - max_raw) / place_temp) for s in raw_scores]
    place_probs = [
        v * 100.0 for v in _harville_place_probs(place_exps, slots=PLACE_SLOTS)
    ]

    rows: list[dict[str, Any]] = []
    for i, e in enumerate(entries):
        rows.append(
            {
                "horse_no": _safe_int(e.get("horse_no", 0)),
                "horse_name": str(e.get("horse_name", "")),
                "win_probability": probs[i],
                "place_probability": place_probs[i],
                "rank": 0,
            }
        )
    rows.sort(key=_win_order_key)
    for rank, row in enumerate(rows, start=1):
        row["rank"] = rank
    return rows


def _win_order_key(p: dict[str, Any]) -> tuple[float, float, int]:
    """단승 지향 정렬(AI 추천 탭과 동일한 순서)."""
    return (-p["win_probability"], -p["place_probability"], p["horse_no"])


def _place_order_key(p: dict[str, Any]) -> tuple[float, float, int]:
    """입상 지향 정렬(종합추천 탭과 동일한 순서)."""
    return (-p["place_probability"], -p["win_probability"], p["horse_no"])


_EMPTY_METRICS: dict[str, float] = {
    "objective": 0.0,
    "top3_match": 0.0,
    "top3_winner": 0.0,
    "place_brier": 1.0,
    "place_recall_at4": 0.0,
    "at_least_2_of_3": 0.0,
    "top1_acc": 0.0,
    "races": 0,
}


def _objective_from(metrics: dict[str, float]) -> float:
    w = OBJECTIVE_WEIGHTS
    return (
        (metrics["top3_match"] * w["top3_match"])
        + (metrics["top3_winner"] * w["top3_winner"])
        + ((1.0 - metrics["place_brier"]) * w["place_brier"])
        + (metrics["top1_acc"] * w["top1_acc"])
    )


def _evaluate(samples: list[dict[str, Any]], params: HeuristicParams) -> dict[str, float]:
    """입상권(Top3) 포함률을 중심으로 예측 품질을 평가한다.

    Top3 선정은 `place_probability` 기준이고, `top1_acc` 만 단승 정렬을 쓴다.
    """
    if not samples:
        return dict(_EMPTY_METRICS)

    top1_hits = 0
    top3_match_sum = 0.0
    top3_winner_hits = 0
    recall4_sum = 0.0
    at_least_2_hits = 0
    brier_sum = 0.0
    total_horses = 0
    scored_races = 0

    for race in samples:
        winner_no = race["winner_no"]
        # 결과가 아직 없는 경주는 정답이 없으므로 평가에서 제외한다.
        if winner_no <= 0:
            continue

        preds = _race_probabilities(
            race["entries"], params, win_odds=race.get("win_odds", {}) or None
        )
        if not preds:
            continue

        actual_top3 = race["actual_top3"] or set()

        win_ranked = sorted(preds, key=_win_order_key)
        place_ranked = sorted(preds, key=_place_order_key)
        pred_top3 = {p["horse_no"] for p in place_ranked[:PLACE_SLOTS]}
        pred_top4 = {p["horse_no"] for p in place_ranked[: PLACE_SLOTS + 1]}

        if win_ranked[0]["horse_no"] == winner_no:
            top1_hits += 1
        if winner_no in pred_top3:
            top3_winner_hits += 1

        if actual_top3:
            denom = min(PLACE_SLOTS, len(actual_top3))
            hits = len(pred_top3 & actual_top3)
            top3_match_sum += hits / denom
            recall4_sum += len(pred_top4 & actual_top3) / denom
            if hits >= 2:
                at_least_2_hits += 1

        for p in preds:
            y = 1.0 if p["horse_no"] in actual_top3 else 0.0
            brier_sum += ((p["place_probability"] / 100.0) - y) ** 2
        total_horses += len(preds)
        scored_races += 1

    if scored_races == 0:
        return dict(_EMPTY_METRICS)

    metrics = {
        "top1_acc": top1_hits / scored_races,
        "top3_match": top3_match_sum / scored_races,
        "top3_winner": top3_winner_hits / scored_races,
        "place_recall_at4": recall4_sum / scored_races,
        "at_least_2_of_3": at_least_2_hits / scored_races,
        "place_brier": brier_sum / max(1, total_horses),
        "races": scored_races,
    }
    metrics["objective"] = _objective_from(metrics)
    return metrics


def _walk_forward_blocks(
    samples: list[dict[str, Any]], folds: int
) -> list[list[dict[str, Any]]]:
    """시간순 샘플을 검증 블록 `folds` 개로 나눈다.

    앞쪽 블록은 as-of 피처 계산의 과거 이력 역할을 하므로 검증에서 제외하고,
    뒤쪽 `folds` 개 블록만 순차적으로 검증에 사용한다.
    """
    n = len(samples)
    if n == 0 or folds < 1:
        return []

    total_blocks = folds + 1
    block_size = n // total_blocks
    if block_size < 1:
        return [samples]

    blocks: list[list[dict[str, Any]]] = []
    for i in range(1, total_blocks):
        start = i * block_size
        end = n if i == total_blocks - 1 else (i + 1) * block_size
        blocks.append(samples[start:end])
    return [b for b in blocks if b]


def _cross_validate(
    blocks: list[list[dict[str, Any]]], params: HeuristicParams
) -> dict[str, Any]:
    """검증 블록별 지표와 그 평균·표준편차를 계산한다."""
    if not blocks:
        return {"objective": 0.0, "objective_std": 0.0, "folds": []}

    fold_metrics = [_evaluate(block, params) for block in blocks]
    objectives = [m["objective"] for m in fold_metrics]
    mean = sum(objectives) / len(objectives)
    variance = sum((o - mean) ** 2 for o in objectives) / len(objectives)

    return {
        "objective": mean,
        "objective_std": math.sqrt(variance),
        "folds": fold_metrics,
    }


def _round_metrics(metrics: dict[str, Any]) -> dict[str, Any]:
    return {
        k: round(v, 6) if isinstance(v, float) else v for k, v in metrics.items()
    }


def _normalize_weights(params: HeuristicParams) -> HeuristicParams:
    total = (
        params.w_rating
        + params.w_perf
        + params.w_class_form
        + params.w_pace
        + params.w_condition
        + params.w_market
        + params.w_jockey
        + params.w_recent_form
        + params.w_fitness
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
        w_jockey=params.w_jockey / total,
        w_recent_form=params.w_recent_form / total,
        w_fitness=params.w_fitness / total,
        rating_pow=params.rating_pow,
        prior_weight=params.prior_weight,
        temp_scale=params.temp_scale,
        place_temp_scale=params.place_temp_scale,
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
            w_jockey=_safe_float(d.get("w_jockey", 0.0), 0.0),
            w_recent_form=_safe_float(d.get("w_recent_form", 0.0), 0.0),
            w_fitness=_safe_float(d.get("w_fitness", 0.0), 0.0),
            rating_pow=_safe_float(d.get("rating_pow", 2.0), 2.0),
            prior_weight=_safe_float(d.get("prior_weight", 7.0), 7.0),
            temp_scale=_safe_float(d.get("temp_scale", 1.0), 1.0),
            place_temp_scale=_safe_float(
                d.get("place_temp_scale", d.get("temp_scale", 1.0)),
                1.0,
            ),
            reliability_penalty=_safe_float(
                d.get("reliability_penalty", 0.15), 0.15
            ),
        )
    )


def _mutate(
    base: HeuristicParams,
    rng: random.Random,
    *,
    allow_market: bool = False,
) -> HeuristicParams:
    def n(value: float, scale: float, lo: float, hi: float) -> float:
        return max(lo, min(hi, value + rng.uniform(-scale, scale)))

    mutated = HeuristicParams(
        w_rating=n(base.w_rating, 0.10, 0.05, 0.65),
        w_perf=n(base.w_perf, 0.10, 0.05, 0.65),
        w_class_form=n(base.w_class_form, 0.08, 0.03, 0.50),
        # 전개 점수는 rating/승률을 재활용한 순환 정의라 탐색이 0까지 내릴 수 있게 둔다.
        w_pace=n(base.w_pace, 0.06, 0.0, 0.35),
        w_condition=n(base.w_condition, 0.06, 0.01, 0.35),
        w_market=n(base.w_market, 0.04, 0.0, 0.30) if allow_market else 0.0,
        w_jockey=n(base.w_jockey, 0.08, 0.0, 0.45),
        w_recent_form=n(base.w_recent_form, 0.10, 0.0, 0.60),
        w_fitness=n(base.w_fitness, 0.08, 0.0, 0.45),
        rating_pow=n(base.rating_pow, 0.25, 0.8, 3.5),
        prior_weight=n(base.prior_weight, 2.5, 2.0, 18.0),
        temp_scale=n(base.temp_scale, 0.20, 0.75, 1.35),
        place_temp_scale=n(base.place_temp_scale, 0.25, 0.60, 2.20),
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
        preds.sort(key=_win_order_key)

        place_rank_by_horse = {
            p["horse_no"]: rank
            for rank, p in enumerate(sorted(preds, key=_place_order_key), start=1)
        }
        # 입상 확률의 기준선은 두수에 따라 달라지므로(무작위 = 슬롯수/두수)
        # 고정 임계값 대신 기준선 대비 배수로 판정한다.
        place_baseline = (PLACE_SLOTS / len(preds)) * 100.0 if preds else 0.0

        for p in preds:
            tags = []
            place_rank = place_rank_by_horse[p["horse_no"]]
            if place_rank == 1:
                tags.append("입상강력")
            elif place_rank <= PLACE_SLOTS:
                tags.append("입상유력")
            if place_baseline > 0 and p["place_probability"] >= place_baseline * 1.5:
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
        include_market_odds=args.include_market_odds,
    )
    if not samples:
        print("튜닝 가능한 경주 데이터가 없습니다.")
        return

    holdout_size = int(len(samples) * HOLDOUT_RATIO)
    search_samples = samples[: len(samples) - holdout_size] if holdout_size else samples
    holdout_samples = samples[len(samples) - holdout_size :] if holdout_size else []

    blocks = _walk_forward_blocks(search_samples, args.folds)
    if not blocks:
        print("walk-forward 검증 블록을 만들 수 없습니다. 표본이 너무 적습니다.")
        return

    print(
        f"[INFO] 전체 {len(samples)}경주 → 탐색 {len(search_samples)} "
        f"(검증 블록 {len(blocks)}개: {[len(b) for b in blocks]}), "
        f"홀드아웃 {len(holdout_samples)}"
    )

    baseline = _normalize_weights(
        HeuristicParams(
            w_rating=0.324359,
            w_perf=0.371729,
            w_class_form=0.020350,
            w_pace=0.005776,
            w_condition=0.277786,
            w_market=0.0,
            # 신규 피처는 중립 가중으로 시작해 탐색이 값어치를 판단하게 한다.
            w_jockey=0.080000,
            w_recent_form=0.120000,
            w_fitness=0.080000,
            rating_pow=2.614967,
            prior_weight=7.375545,
            temp_scale=1.595725,
            place_temp_scale=1.000000,
            reliability_penalty=0.174242,
        )
    )
    best_params = baseline
    best_cv = _cross_validate(blocks, baseline)

    print(
        "[BASE] objective={:.4f}(±{:.4f}) folds={}".format(
            best_cv["objective"],
            best_cv["objective_std"],
            [round(f["top3_match"], 3) for f in best_cv["folds"]],
        )
    )

    for trial in range(1, args.trials + 1):
        candidate = (
            _mutate(best_params, rng, allow_market=args.include_market_odds)
            if trial > 1
            else baseline
        )
        cv = _cross_validate(blocks, candidate)
        if cv["objective"] > best_cv["objective"]:
            best_params = candidate
            best_cv = cv
            print(
                "[BEST {:04d}] objective={:.4f}(±{:.4f}) folds={}".format(
                    trial,
                    cv["objective"],
                    cv["objective_std"],
                    [round(f["top3_match"], 3) for f in cv["folds"]],
                )
            )

    cv_aggregate = _evaluate(
        [race for block in blocks for race in block], best_params
    )
    holdout_metrics = (
        _evaluate(holdout_samples, best_params) if holdout_samples else dict(_EMPTY_METRICS)
    )

    print("-" * 60)
    print(
        "[CV ] top3_match={:.3f} top3_winner={:.3f} place_brier={:.4f} "
        "recall@4={:.3f} 2of3={:.3f} top1={:.3f}".format(
            cv_aggregate["top3_match"],
            cv_aggregate["top3_winner"],
            cv_aggregate["place_brier"],
            cv_aggregate["place_recall_at4"],
            cv_aggregate["at_least_2_of_3"],
            cv_aggregate["top1_acc"],
        )
    )
    if holdout_samples:
        print(
            "[HOLD] top3_match={:.3f} top3_winner={:.3f} place_brier={:.4f} "
            "recall@4={:.3f} 2of3={:.3f} top1={:.3f}".format(
                holdout_metrics["top3_match"],
                holdout_metrics["top3_winner"],
                holdout_metrics["place_brier"],
                holdout_metrics["place_recall_at4"],
                holdout_metrics["at_least_2_of_3"],
                holdout_metrics["top1_acc"],
            )
        )
        gap = cv_aggregate["top3_match"] - holdout_metrics["top3_match"]
        if gap > best_cv["objective_std"] * 2:
            print(
                f"  → 경고: CV와 홀드아웃 top3_match 격차 {gap:.3f} 가 "
                f"fold 표준편차의 2배를 넘습니다. 과적합을 의심하십시오."
            )
    print("-" * 60)

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
            "folds": args.folds,
            "include_market_odds": args.include_market_odds,
        },
        "cv_metrics": _round_metrics(cv_aggregate),
        "cv_objective_mean": round(best_cv["objective"], 6),
        "cv_objective_std": round(best_cv["objective_std"], 6),
        "fold_metrics": [_round_metrics(m) for m in best_cv["folds"]],
        "metrics": _round_metrics(holdout_metrics),
        "objective_weights": dict(OBJECTIVE_WEIGHTS),
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
