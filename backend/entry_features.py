"""출마표 항목별 as-of 시계열 피처 계산.

`race_results` 의 과거 이력만으로 기수 입상률, 최근 폼, 거리 적성·체중 변화를
0~1 서브스코어로 환산한다. 모든 집계는 **대상 경주일 이전** 데이터만 사용해
결과 누출을 막는다.

같은 계산이 `lib/core/services/entry_features.dart` 에도 포팅되어 있으므로
공식을 바꿀 때는 양쪽을 함께 수정해야 한다.
"""

from __future__ import annotations

from bisect import bisect_left
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Iterable

# 기수 집계 창(일)과 베이지안 prior 표본 수.
JOCKEY_WINDOW_DAYS = 365
JOCKEY_PRIOR_SAMPLES = 20.0

# 최근 폼에 반영할 직전 경주 수.
RECENT_FORM_RACES = 5

# 거리 적성으로 묶는 범위(±m)와 prior 표본 수.
DISTANCE_BAND_METERS = 200
DISTANCE_PRIOR_SAMPLES = 6.0

# 입상권으로 인정하는 착순.
PLACE_SLOTS = 3

# 피처가 없을 때 쓰는 중립값. 점수에 영향을 주지 않는다.
NEUTRAL_SCORE = 0.5

# entry dict 에 계산 결과를 붙일 때 쓰는 키.
JOCKEY_FEATURE_KEY = "_feat_jockey"
RECENT_FORM_FEATURE_KEY = "_feat_recent_form"
FITNESS_FEATURE_KEY = "_feat_fitness"


@dataclass(frozen=True)
class EntryFeatureScores:
    jockey: float
    recent_form: float
    fitness: float


NEUTRAL_FEATURES = EntryFeatureScores(
    jockey=NEUTRAL_SCORE,
    recent_form=NEUTRAL_SCORE,
    fitness=NEUTRAL_SCORE,
)


@dataclass(frozen=True)
class _Record:
    day: date
    race_no: int
    rank: int
    field_size: int
    distance: int
    horse_weight: float

    @property
    def sort_key(self) -> tuple[date, int]:
        """같은 날 두 번 출전해도 순서가 흔들리지 않도록 경주 번호까지 쓴다."""
        return (self.day, self.race_no)

    @property
    def placed(self) -> bool:
        return 1 <= self.rank <= PLACE_SLOTS

    @property
    def finish_quality(self) -> float:
        """1착이면 1.0, 꼴찌면 0.0 이 되는 착순 백분위."""
        if self.rank <= 0 or self.field_size <= 1:
            return NEUTRAL_SCORE
        return _clamp01(1.0 - ((self.rank - 1) / (self.field_size - 1)))


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def _parse_day(value: Any) -> date | None:
    text = str(value or "").strip()
    if len(text) != 8 or not text.isdigit():
        return None
    try:
        return datetime.strptime(text, "%Y%m%d").date()
    except ValueError:
        return None


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


def _relative_to_prior(rate: float, prior_rate: float) -> float:
    """비율을 전체 평균 대비 0~1 점수로 환산한다.

    평균과 같으면 0.5, 평균의 두 배 이상이면 1.0, 0이면 0.0 이 된다.
    경마장·두수 분포가 달라져도 스스로 보정되도록 절대 임계값을 쓰지 않는다.
    """
    if prior_rate <= 0:
        return NEUTRAL_SCORE
    return _clamp01(0.5 + ((rate - prior_rate) / (2.0 * prior_rate)))


def _smoothed_place_rate(
    records: list[_Record], prior_rate: float, prior_samples: float
) -> float:
    n = len(records)
    hits = sum(1 for r in records if r.placed)
    return (hits + (prior_rate * prior_samples)) / (n + prior_samples)


def _rest_score(days_since_last: int | None) -> float:
    """휴양 기간 점수. 너무 촘촘하거나 너무 오래 쉬면 감점한다."""
    if days_since_last is None:
        return NEUTRAL_SCORE
    if 14 <= days_since_last <= 60:
        return 1.0
    if 7 <= days_since_last < 14 or 60 < days_since_last <= 120:
        return 0.8
    return 0.5


def _weight_change_score(current: float, previous: float | None) -> float:
    """직전 경주 대비 마체중 변화 점수. 변동이 클수록 감점한다."""
    if previous is None or current <= 0 or previous <= 0:
        return 0.6
    delta = abs(current - previous)
    if delta <= 4:
        return 1.0
    if delta <= 8:
        return 0.7
    if delta <= 12:
        return 0.4
    return 0.2


def _trend_score(records: list[_Record]) -> float:
    """최근 2경주 성적이 그 이전 3경주보다 좋아졌는지."""
    if len(records) < 3:
        return NEUTRAL_SCORE
    recent = records[-2:]
    earlier = records[-RECENT_FORM_RACES:-2]
    if not earlier:
        return NEUTRAL_SCORE
    recent_avg = sum(r.finish_quality for r in recent) / len(recent)
    earlier_avg = sum(r.finish_quality for r in earlier) / len(earlier)
    return _clamp01(0.5 + ((recent_avg - earlier_avg) / 2.0))


def _weighted_finish_quality(records: list[_Record]) -> float:
    """최근 경주일수록 크게 반영하는 착순 백분위 평균."""
    if not records:
        return NEUTRAL_SCORE
    weighted = 0.0
    weight_sum = 0.0
    for offset, record in enumerate(reversed(records), start=1):
        weight = 1.0 / offset
        weighted += record.finish_quality * weight
        weight_sum += weight
    return _clamp01(weighted / weight_sum) if weight_sum > 0 else NEUTRAL_SCORE


class AsOfFeatureIndex:
    """경주일 이전 이력만 조회하도록 정렬해 둔 `race_results` 인덱스."""

    def __init__(self, results: Iterable[dict[str, Any]]):
        rows = list(results)
        field_sizes = self._field_sizes(rows)

        by_horse: dict[str, list[_Record]] = {}
        by_jockey: dict[str, list[_Record]] = {}
        placed_total = 0
        record_total = 0

        for row in rows:
            day = _parse_day(row.get("race_date"))
            rank = _to_int(row.get("rank", 0))
            if day is None or rank <= 0:
                continue

            race_no = _to_int(row.get("race_no", 0))
            key = (
                str(row.get("meet", "")),
                str(row.get("race_date", "")),
                race_no,
            )
            record = _Record(
                day=day,
                race_no=race_no,
                rank=rank,
                field_size=field_sizes.get(key, 0),
                distance=_to_int(row.get("distance", 0)),
                horse_weight=_to_float(row.get("horse_weight", 0.0)),
            )

            horse = str(row.get("horse_name", "")).strip()
            if horse:
                by_horse.setdefault(horse, []).append(record)
            jockey = str(row.get("jockey_name", "")).strip()
            if jockey:
                by_jockey.setdefault(jockey, []).append(record)

            record_total += 1
            placed_total += int(record.placed)

        for records in by_horse.values():
            records.sort(key=lambda r: r.sort_key)
        for records in by_jockey.values():
            records.sort(key=lambda r: r.sort_key)

        self._by_horse = by_horse
        self._by_jockey = by_jockey
        self._horse_days = {k: [r.day for r in v] for k, v in by_horse.items()}
        self._jockey_days = {k: [r.day for r in v] for k, v in by_jockey.items()}
        self.prior_place_rate = (
            (placed_total / record_total) if record_total else 0.25
        )
        self.record_count = record_total

    @staticmethod
    def _field_sizes(rows: list[dict[str, Any]]) -> dict[tuple[str, str, int], int]:
        sizes: dict[tuple[str, str, int], int] = {}
        for row in rows:
            if _to_int(row.get("rank", 0)) <= 0:
                continue
            key = (
                str(row.get("meet", "")),
                str(row.get("race_date", "")),
                _to_int(row.get("race_no", 0)),
            )
            sizes[key] = sizes.get(key, 0) + 1
        return sizes

    def _history_before(
        self,
        records: list[_Record] | None,
        days: list[date] | None,
        cutoff: date,
    ) -> list[_Record]:
        if not records or not days:
            return []
        end = bisect_left(days, cutoff)
        return records[:end]

    def horse_history(self, horse_name: str, cutoff: date) -> list[_Record]:
        name = horse_name.strip()
        return self._history_before(
            self._by_horse.get(name), self._horse_days.get(name), cutoff
        )

    def jockey_history(self, jockey_name: str, cutoff: date) -> list[_Record]:
        name = jockey_name.strip()
        return self._history_before(
            self._by_jockey.get(name), self._jockey_days.get(name), cutoff
        )

    def jockey_score(self, jockey_name: str, cutoff: date) -> float:
        history = self.jockey_history(jockey_name, cutoff)
        if not history:
            return NEUTRAL_SCORE
        window_start = cutoff.toordinal() - JOCKEY_WINDOW_DAYS
        recent = [r for r in history if r.day.toordinal() >= window_start]
        if not recent:
            return NEUTRAL_SCORE
        rate = _smoothed_place_rate(
            recent, self.prior_place_rate, JOCKEY_PRIOR_SAMPLES
        )
        return _relative_to_prior(rate, self.prior_place_rate)

    def recent_form_score(self, horse_name: str, cutoff: date) -> float:
        history = self.horse_history(horse_name, cutoff)
        if not history:
            return NEUTRAL_SCORE
        window = history[-RECENT_FORM_RACES:]
        days_since = (cutoff - history[-1].day).days
        return _clamp01(
            (_weighted_finish_quality(window) * 0.60)
            + (_trend_score(window) * 0.20)
            + (_rest_score(days_since) * 0.20)
        )

    def fitness_score(
        self, horse_name: str, cutoff: date, distance: int, horse_weight: float
    ) -> float:
        history = self.horse_history(horse_name, cutoff)
        if not history:
            return NEUTRAL_SCORE

        if distance > 0:
            same_band = [
                r
                for r in history
                if r.distance > 0
                and abs(r.distance - distance) <= DISTANCE_BAND_METERS
            ]
        else:
            same_band = []

        if same_band:
            rate = _smoothed_place_rate(
                same_band, self.prior_place_rate, DISTANCE_PRIOR_SAMPLES
            )
            distance_score = _relative_to_prior(rate, self.prior_place_rate)
        else:
            distance_score = NEUTRAL_SCORE

        previous_weight = next(
            (r.horse_weight for r in reversed(history) if r.horse_weight > 0), None
        )
        weight_score = _weight_change_score(horse_weight, previous_weight)

        return _clamp01((distance_score * 0.60) + (weight_score * 0.40))

    def features_for(
        self,
        *,
        race_date: str,
        horse_name: str,
        jockey_name: str,
        distance: int,
        horse_weight: float,
    ) -> EntryFeatureScores:
        cutoff = _parse_day(race_date)
        if cutoff is None:
            return NEUTRAL_FEATURES
        return EntryFeatureScores(
            jockey=self.jockey_score(jockey_name, cutoff),
            recent_form=self.recent_form_score(horse_name, cutoff),
            fitness=self.fitness_score(horse_name, cutoff, distance, horse_weight),
        )

    def attach_to_entries(
        self,
        entries: Iterable[dict[str, Any]],
        *,
        race_date: str,
        distance: int,
    ) -> None:
        """entry dict 에 서브스코어를 직접 기록한다."""
        for entry in entries:
            scores = self.features_for(
                race_date=race_date,
                horse_name=str(entry.get("horse_name", "")),
                jockey_name=str(entry.get("jockey_name", "")),
                distance=distance,
                horse_weight=_to_float(entry.get("horse_weight", 0.0)),
            )
            entry[JOCKEY_FEATURE_KEY] = scores.jockey
            entry[RECENT_FORM_FEATURE_KEY] = scores.recent_form
            entry[FITNESS_FEATURE_KEY] = scores.fitness
