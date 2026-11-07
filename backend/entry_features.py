"""출마표 항목별 as-of 시계열 피처 계산.

`race_results` 의 과거 이력만으로 기수·조교사 입상률, 마·기수 조합,
최근 폼, 거리 적성·체중 변화, 통과순위 주행유형을 환산한다. 모든 집계는
**대상 경주일 이전** 데이터만 사용해 결과 누출을 막는다.

같은 계산이 `lib/core/services/entry_features.dart` 에도 포팅되어 있으므로
공식을 바꿀 때는 양쪽을 함께 수정해야 한다.
"""

from __future__ import annotations

import re
from bisect import bisect_left
from collections import Counter
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Iterable

# 기수·조교사 집계 창(일)과 베이지안 prior 표본 수.
JOCKEY_WINDOW_DAYS = 365
JOCKEY_PRIOR_SAMPLES = 20.0
TRAINER_WINDOW_DAYS = 365
TRAINER_PRIOR_SAMPLES = 20.0

# 마·기수 조합. 365일 창 표본이 이보다 적으면 전 기간을 쓴다.
COMBO_WINDOW_DAYS = 365
COMBO_PRIOR_SAMPLES = 20.0
COMBO_MIN_WINDOW_SAMPLES = 3

# 최근 폼에 반영할 직전 경주 수.
RECENT_FORM_RACES = 5

# 주행 유형: 직전 경주 통과순위 표본. 이보다 적으면 레이팅 휴리스틱으로 넘긴다.
RUNNING_STYLE_RACES = 5
RUNNING_STYLE_MIN_SAMPLES = 2
_KNOWN_RUNNING_STYLES = ("선행", "선입", "중단", "추입")
_PASS_ORDER_SPLIT = re.compile(r"[-–—,/\s]+")
_NON_DIGIT = re.compile(r"[^\d]")

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
TRAINER_FEATURE_KEY = "_feat_trainer"
COMBO_FEATURE_KEY = "_feat_combo"
RUNNING_STYLE_FEATURE_KEY = "_feat_running_style"
SPEED_FEATURE_KEY = "_feat_speed"
BURDEN_FEATURE_KEY = "_feat_burden"
GATE_FEATURE_KEY = "_feat_gate"


@dataclass(frozen=True)
class EntryFeatureScores:
    jockey: float
    recent_form: float
    fitness: float
    trainer: float
    combo: float
    speed: float = NEUTRAL_SCORE
    burden: float = NEUTRAL_SCORE
    gate: float = NEUTRAL_SCORE
    running_style: str = ""


NEUTRAL_FEATURES = EntryFeatureScores(
    jockey=NEUTRAL_SCORE,
    recent_form=NEUTRAL_SCORE,
    fitness=NEUTRAL_SCORE,
    trainer=NEUTRAL_SCORE,
    combo=NEUTRAL_SCORE,
    speed=NEUTRAL_SCORE,
    burden=NEUTRAL_SCORE,
    gate=NEUTRAL_SCORE,
    running_style="",
)


@dataclass(frozen=True)
class _Record:
    day: date
    race_no: int
    meet: str
    rank: int
    field_size: int
    distance: int
    race_time_seconds: float
    carried_weight: float
    horse_weight: float
    pass_order: str = ""

    @property
    def sort_key(self) -> tuple[date, int, str]:
        """같은 날 두 번 출전해도 순서가 흔들리지 않도록 경주 번호까지 쓴다."""
        return (self.day, self.race_no, self.meet)

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


def parse_race_time_seconds(value: Any) -> float:
    """KRA `M:SS.s` 또는 초 단위 경주기록을 초로 변환한다."""
    text = str(value or "").strip()
    if not text:
        return 0.0
    try:
        if ":" not in text:
            seconds = float(text)
            return seconds if seconds > 0 else 0.0
        minutes_text, seconds_text = text.split(":", 1)
        seconds = (float(minutes_text) * 60.0) + float(seconds_text)
        return seconds if seconds > 0 else 0.0
    except (TypeError, ValueError):
        return 0.0


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


def _combo_key(horse_name: str, jockey_name: str) -> str | None:
    horse = horse_name.strip()
    jockey = jockey_name.strip()
    if not horse or not jockey:
        return None
    return f"{horse}\u001f{jockey}"


def parse_pass_order_style(pass_order: str, field_size: int) -> str:
    """통과순위에서 선행/선입/중단/추입을 읽는다. 모르면 빈 문자열.

    `1-1-1-1`, `8-7-5-3` 처럼 첫 구간 위치를 두수 대비 비율로 본다.
    문자열에 한글 유형이 있으면 숫자보다 우선한다.
    """
    text = str(pass_order or "").strip()
    if not text:
        return ""
    for label in _KNOWN_RUNNING_STYLES:
        if label in text:
            return label

    first: int | None = None
    for part in _PASS_ORDER_SPLIT.split(text):
        digits = _NON_DIGIT.sub("", part)
        if not digits:
            continue
        try:
            value = int(digits)
        except ValueError:
            continue
        if value > 0:
            first = value
            break
    if first is None:
        return ""
    if first <= 2:
        return "선행"
    if field_size <= 1:
        return ""
    ratio = first / field_size
    if ratio <= 0.25:
        return "선행"
    if ratio <= 0.45:
        return "선입"
    if ratio <= 0.70:
        return "중단"
    return "추입"


def running_style_from_records(records: list[_Record]) -> str:
    """직전 최대 5경주 통과순위의 최빈 유형. 유효 표본이 2건 미만이면 빈 문자열."""
    if not records:
        return ""
    window = records[-RUNNING_STYLE_RACES:]
    styles: list[str] = []
    for record in reversed(window):
        style = parse_pass_order_style(record.pass_order, record.field_size)
        if style:
            styles.append(style)
    if len(styles) < RUNNING_STYLE_MIN_SAMPLES:
        return ""
    counts = Counter(styles)
    best = max(counts.values())
    for style in styles:
        if counts[style] == best:
            return style
    return ""


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
        by_trainer: dict[str, list[_Record]] = {}
        by_combo: dict[str, list[_Record]] = {}
        all_records: list[_Record] = []
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
                meet=str(row.get("meet", "")).strip(),
                rank=rank,
                field_size=field_sizes.get(key, 0),
                distance=_to_int(row.get("distance", 0)),
                race_time_seconds=parse_race_time_seconds(row.get("race_time")),
                carried_weight=_to_float(row.get("weight", 0.0)),
                horse_weight=_to_float(row.get("horse_weight", 0.0)),
                pass_order=str(row.get("pass_order", "") or "").strip(),
            )
            all_records.append(record)

            horse = str(row.get("horse_name", "")).strip()
            if horse:
                by_horse.setdefault(horse, []).append(record)
            jockey = str(row.get("jockey_name", "")).strip()
            if jockey:
                by_jockey.setdefault(jockey, []).append(record)
            trainer = str(row.get("trainer_name", "")).strip()
            if trainer:
                by_trainer.setdefault(trainer, []).append(record)
            combo = _combo_key(horse, jockey)
            if combo:
                by_combo.setdefault(combo, []).append(record)

            record_total += 1
            placed_total += int(record.placed)

        for group in (by_horse, by_jockey, by_trainer, by_combo):
            for records in group.values():
                records.sort(key=lambda r: r.sort_key)

        self._by_horse = by_horse
        self._by_jockey = by_jockey
        self._by_trainer = by_trainer
        self._by_combo = by_combo
        self._horse_days = {k: [r.day for r in v] for k, v in by_horse.items()}
        self._jockey_days = {k: [r.day for r in v] for k, v in by_jockey.items()}
        self._trainer_days = {k: [r.day for r in v] for k, v in by_trainer.items()}
        self._combo_days = {k: [r.day for r in v] for k, v in by_combo.items()}
        all_records.sort(key=lambda r: r.sort_key)
        self._all_records = all_records
        self._all_days = [r.day for r in all_records]
        self.prior_place_rate = (
            (placed_total / record_total) if record_total else 0.25
        )
        self.record_count = record_total

    def _prior_place_rate_before(self, cutoff: date) -> float:
        end = bisect_left(self._all_days, cutoff)
        if end <= 0:
            return 0.25
        records = self._all_records[:end]
        return sum(1 for record in records if record.placed) / len(records)

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

    def trainer_history(self, trainer_name: str, cutoff: date) -> list[_Record]:
        name = trainer_name.strip()
        return self._history_before(
            self._by_trainer.get(name), self._trainer_days.get(name), cutoff
        )

    def combo_history(
        self, horse_name: str, jockey_name: str, cutoff: date
    ) -> list[_Record]:
        key = _combo_key(horse_name, jockey_name)
        if key is None:
            return []
        return self._history_before(
            self._by_combo.get(key), self._combo_days.get(key), cutoff
        )

    def _windowed_place_score(
        self,
        history: list[_Record],
        cutoff: date,
        window_days: int,
        prior_samples: float,
        *,
        fallback_to_all: bool = False,
        min_window_samples: int = 1,
    ) -> float:
        if not history:
            return NEUTRAL_SCORE
        window_start = cutoff.toordinal() - window_days
        recent = [r for r in history if r.day.toordinal() >= window_start]
        if not recent:
            if not fallback_to_all:
                return NEUTRAL_SCORE
            recent = history
        elif fallback_to_all and len(recent) < min_window_samples:
            recent = history
        prior = self._prior_place_rate_before(cutoff)
        rate = _smoothed_place_rate(recent, prior, prior_samples)
        return _relative_to_prior(rate, prior)

    def jockey_score(self, jockey_name: str, cutoff: date, meet: str = "") -> float:
        history = self.jockey_history(jockey_name, cutoff)
        venue = [record for record in history if meet and record.meet == meet]
        return self._windowed_place_score(
            venue if len(venue) >= 3 else history,
            cutoff,
            JOCKEY_WINDOW_DAYS,
            JOCKEY_PRIOR_SAMPLES,
        )

    def trainer_score(self, trainer_name: str, cutoff: date, meet: str = "") -> float:
        history = self.trainer_history(trainer_name, cutoff)
        venue = [record for record in history if meet and record.meet == meet]
        return self._windowed_place_score(
            venue if len(venue) >= 3 else history,
            cutoff,
            TRAINER_WINDOW_DAYS,
            TRAINER_PRIOR_SAMPLES,
        )

    def combo_score(
        self, horse_name: str, jockey_name: str, cutoff: date
    ) -> float:
        return self._windowed_place_score(
            self.combo_history(horse_name, jockey_name, cutoff),
            cutoff,
            COMBO_WINDOW_DAYS,
            COMBO_PRIOR_SAMPLES,
            fallback_to_all=True,
            min_window_samples=COMBO_MIN_WINDOW_SAMPLES,
        )

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
            prior = self._prior_place_rate_before(cutoff)
            rate = _smoothed_place_rate(
                same_band, prior, DISTANCE_PRIOR_SAMPLES
            )
            distance_score = _relative_to_prior(rate, prior)
        else:
            distance_score = NEUTRAL_SCORE

        previous_weight = next(
            (r.horse_weight for r in reversed(history) if r.horse_weight > 0), None
        )
        weight_score = _weight_change_score(horse_weight, previous_weight)

        return _clamp01((distance_score * 0.60) + (weight_score * 0.40))

    def running_style(self, horse_name: str, cutoff: date) -> str:
        return running_style_from_records(self.horse_history(horse_name, cutoff))

    def speed_score(self, horse_name: str, cutoff: date, meet: str = "") -> float:
        history = self.horse_history(horse_name, cutoff)
        venue = [
            r
            for r in history
            if meet
            and r.meet == meet
            and r.race_time_seconds > 0
            and r.distance > 0
        ]
        valid = venue if len(venue) >= 2 else [
            r for r in history if r.race_time_seconds > 0 and r.distance > 0
        ]
        if not valid:
            return NEUTRAL_SCORE
        per_100m = [
            r.race_time_seconds / (r.distance / 100.0) for r in valid[-5:]
        ]
        average = sum(per_100m) / len(per_100m)
        return _clamp01(0.5 + ((6.5 - average) / 2.0))

    def burden_score(
        self,
        horse_name: str,
        cutoff: date,
        carried_weight: float,
        horse_weight: float,
    ) -> float:
        history = self.horse_history(horse_name, cutoff)
        previous = next(
            (r.carried_weight for r in reversed(history) if r.carried_weight > 0),
            None,
        )
        if previous is None or carried_weight <= 0:
            delta_score = NEUTRAL_SCORE
        else:
            delta = carried_weight - previous
            # 증량은 부담, 감량은 이점으로 보되 극단값은 제한한다.
            delta_score = _clamp01(0.75 - (delta * 0.12))
        if carried_weight > 0 and horse_weight > 0:
            ratio = carried_weight / horse_weight
            ratio_score = _clamp01(0.5 + ((0.12 - ratio) / 0.04))
        else:
            ratio_score = NEUTRAL_SCORE
        return _clamp01((delta_score * 0.45) + (ratio_score * 0.55))

    @staticmethod
    def gate_score(horse_no: int, field_size: int) -> float:
        if horse_no <= 0 or field_size <= 1:
            return NEUTRAL_SCORE
        return _clamp01(1.0 - ((horse_no - 1) / (field_size - 1)))

    def features_for(
        self,
        *,
        race_date: str,
        meet: str = "",
        horse_name: str,
        jockey_name: str,
        trainer_name: str = "",
        distance: int,
        carried_weight: float = 0.0,
        horse_weight: float,
        horse_no: int = 0,
        field_size: int = 0,
    ) -> EntryFeatureScores:
        cutoff = _parse_day(race_date)
        if cutoff is None:
            return NEUTRAL_FEATURES
        return EntryFeatureScores(
            jockey=self.jockey_score(jockey_name, cutoff, meet),
            recent_form=self.recent_form_score(horse_name, cutoff),
            fitness=self.fitness_score(horse_name, cutoff, distance, horse_weight),
            trainer=self.trainer_score(trainer_name, cutoff, meet),
            combo=self.combo_score(horse_name, jockey_name, cutoff),
            speed=self.speed_score(horse_name, cutoff, meet),
            burden=self.burden_score(
                horse_name, cutoff, carried_weight, horse_weight
            ),
            gate=self.gate_score(horse_no, field_size),
            running_style=self.running_style(horse_name, cutoff),
        )

    def attach_to_entries(
        self,
        entries: Iterable[dict[str, Any]],
        *,
        race_date: str,
        meet: str,
        distance: int,
    ) -> None:
        """entry dict 에 서브스코어를 직접 기록한다."""
        materialized = list(entries)
        for entry in materialized:
            scores = self.features_for(
                race_date=race_date,
                meet=meet,
                horse_name=str(entry.get("horse_name", "")),
                jockey_name=str(entry.get("jockey_name", "")),
                trainer_name=str(entry.get("trainer_name", "")),
                distance=distance,
                carried_weight=_to_float(entry.get("weight", 0.0)),
                horse_weight=_to_float(entry.get("horse_weight", 0.0)),
                horse_no=_to_int(entry.get("horse_no", 0)),
                field_size=len(materialized),
            )
            entry[JOCKEY_FEATURE_KEY] = scores.jockey
            entry[RECENT_FORM_FEATURE_KEY] = scores.recent_form
            entry[FITNESS_FEATURE_KEY] = scores.fitness
            entry[TRAINER_FEATURE_KEY] = scores.trainer
            entry[COMBO_FEATURE_KEY] = scores.combo
            entry[SPEED_FEATURE_KEY] = scores.speed
            entry[BURDEN_FEATURE_KEY] = scores.burden
            entry[GATE_FEATURE_KEY] = scores.gate
            entry[RUNNING_STYLE_FEATURE_KEY] = scores.running_style
