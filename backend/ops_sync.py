"""
Supabase 운영 파이프라인: KRA 배당(odds) 백필, 휴리스틱 predictions 동기화.

  # 날짜 구간(YYYYMMDD)
  python backend/ops_sync.py odds --since 20260401 --until 20260430 --max-races 200 --sleep 0.35

  # 시행일 하루만
  python backend/ops_sync.py odds --on 20260426 --meet 1

  # races 전체(주의: 경주 수만큼 KRA 호출) — --max-races 0 = 상한 없음
  python backend/ops_sync.py odds --max-races 0 --sleep 0.4

  # 휴리스틱 predictions — on/since/until/tune과 동일 필터
  python backend/ops_sync.py predictions --on 20260426

필수 환경변수: SUPABASE_URL, SUPABASE_SERVICE_KEY, (odds) KRA_SERVICE_KEY

참고: [e오늘의 경주](https://todayrace.kra.co.kr/main.do) 는 서울/제주/부경·일자별
경주 보기(사람용 UI)에 적합합니다. 자동 ETL은 공공데이터 KRA API + Supabase `races` 가
정합/유지보수 측면에서 유리하며, todayrace는 HTML/세션/폼(`selectRaceList.do` 등)에
의존해 스크래핑으로 쓰기는 취약합니다(앱의 `ApiConstants.todayRace* 참고).

자동 실행:
  - GitHub Actions: `.github/workflows/ops-sync.yml` (배당+predictions), `scheduled-tune.yml` (주간 튜닝+아티팩트)
  - 서버/cron: `scripts/scheduled_ops.sh`, (튜닝) `scripts/scheduled_tune.sh`
  - Windows: `scripts/scheduled_ops.ps1`
"""

from __future__ import annotations

import argparse
import json
import os
import time
from datetime import datetime, timezone
from typing import Any

import httpx
from supabase import create_client

from config import KRA_BASE_URL, KRA_SERVICE_KEY, SUPABASE_SERVICE_KEY, SUPABASE_URL
from prediction_constants import MAX_TRAINING_RACES, MODEL_VERSION
from tune_heuristic_predictions import (
    PLACE_SLOTS,
    _build_race_dataset,
    _fetch_all_rows,
    _filter_by_race_date,
    _is_prerace_capture,
    _place_order_key,
    _safe_float,
    _safe_int,
    _sync_predictions,
    _win_order_key,
    heuristic_params_from_dict,
)

API5_ODD_INFO = "/API5/oddInfo"


def _parse_kra_item_list(data: dict) -> list[dict]:
    header = (data or {}).get("response", {}).get("header", {})
    result_code = str(header.get("resultCode", "00"))
    if result_code not in ("00", "0000"):
        return []
    body = (data or {}).get("response", {}).get("body")
    if body is None:
        return []
    items = (body.get("items") or {}).get("item")
    if items is None:
        return []
    if isinstance(items, list):
        return [x for x in items if isinstance(x, dict)]
    if isinstance(items, dict):
        return [items]
    return []


def fetch_odd_info_api5(
    meet: str,
    rc_date: str,
    rc_no: int | None,
) -> list[dict]:
    """앱 `KraApiService.getOddInfo`와 동일: `/API5/oddInfo`, `rc_date` 8자리."""
    if not KRA_SERVICE_KEY:
        raise RuntimeError("KRA_SERVICE_KEY 가 필요합니다.")
    base = (KRA_BASE_URL or "https://apis.data.go.kr/B551015").rstrip("/")
    url = f"{base}{API5_ODD_INFO}"
    params: dict[str, Any] = {
        "ServiceKey": KRA_SERVICE_KEY,
        "_type": "json",
        "meet": str(meet),
        "pageNo": 1,
        "numOfRows": 500,
    }
    if len(rc_date) == 8:
        params["rc_date"] = rc_date
    if rc_no is not None and rc_no > 0:
        params["rc_no"] = rc_no

    with httpx.Client(timeout=45.0) as client:
        resp = client.get(url, params=params)
        resp.raise_for_status()
        return _parse_kra_item_list(resp.json())


def _normalize_bet_type(raw: str) -> str:
    s = (raw or "").strip().upper()
    if s in ("1", "01", "WIN", "S", "단승", "DAN"):
        return "WIN"
    if s in ("2", "02", "PLC", "P", "연승", "EON"):
        return "PLC"
    if s in ("3", "QNL", "복승"):
        return "QNL"
    if s in ("4", "EXA", "쌍승"):
        return "EXA"
    if s in ("5", "TLA", "삼복승"):
        return "TLA"
    if s in ("6", "TRI", "삼쌍승"):
        return "TRI"
    if not s:
        return "UNK"
    return s


def _races_with_prerace_odds(client: Any) -> set[tuple[str, str, int]]:
    """이미 사전 배당 스냅샷을 가진 경주 키 집합.

    사후 확정 배당으로 덮어써 스냅샷을 잃지 않도록 재수집에서 제외한다.
    """
    rows = _fetch_all_rows(
        client, "odds", "meet,race_date,race_no,bet_type,captured_at"
    )
    keys: set[tuple[str, str, int]] = set()
    for row in rows:
        if str(row.get("bet_type", "")).upper() != "WIN":
            continue
        race_date = str(row.get("race_date", ""))
        if _is_prerace_capture(row.get("captured_at"), race_date):
            keys.add(
                (str(row.get("meet", "")), race_date, _safe_int(row.get("race_no", 0)))
            )
    return keys


def _item_row_for_race(
    meet: str, race_date: str, race_no: int, item: dict, captured_at: str
) -> dict | None:
    bet_raw = str(
        item.get("betType")
        or item.get("bettKindCd")
        or item.get("bettKindNm")
        or ""
    )
    bet = _normalize_bet_type(bet_raw)
    rate = _safe_float(
        item.get("bettRt") or item.get("odds") or item.get("rate") or 0, 0.0
    )
    if rate <= 0 and bet not in ("UNK",):
        return None

    h1 = _safe_int(item.get("hrNo1") or item.get("winHrsNo") or 0, 0)
    h2 = _safe_int(item.get("hrNo2") or item.get("plcHrsNo") or 0, 0)
    h3 = _safe_int(item.get("hrNo3") or item.get("trdHrsNo") or 0, 0)
    if h1 <= 0 and bet == "WIN":
        return None

    item_rc = _safe_int(item.get("rcNo") or item.get("raceNo") or 0, 0)
    if item_rc > 0 and item_rc != race_no:
        return None
    it_date = str(item.get("rcDate") or item.get("race_date") or "")
    if it_date and len(it_date) == 8 and it_date != race_date:
        return None

    if rate <= 0:
        return None

    return {
        "meet": meet,
        "race_date": race_date,
        "race_no": race_no,
        "bet_type": bet,
        "horse_no1": h1,
        "horse_no2": h2,
        "horse_no3": h3,
        "rate": float(rate),
        # DB 기본값(NOW())에 맡기면 upsert 시 갱신되지 않아 실제 수집 시각과
        # 어긋난다. 사전/사후 배당 판정을 위해 명시적으로 기록한다.
        "captured_at": captured_at,
    }


def _list_race_keys(
    client: Any,
    meet: str | None,
    since: str | None,
    until: str | None,
    on: str | None,
    max_races: int,
) -> list[dict[str, Any]]:
    rows = _fetch_all_rows(client, "races", "meet,race_date,race_no")
    if meet:
        rows = [r for r in rows if str(r.get("meet", "")) == meet]
    if on and len(str(on)) == 8:
        o = str(on)
        rows = [r for r in rows if str(r.get("race_date", "")) == o]
    else:
        if since:
            rows = [r for r in rows if str(r.get("race_date", "")) >= since]
        if until:
            rows = [r for r in rows if str(r.get("race_date", "")) <= until]
    rows.sort(
        key=lambda r: (str(r.get("race_date", "")), str(r.get("meet", "")), r.get("race_no", 0)),
        reverse=True,
    )
    return rows[:max_races] if max_races > 0 else rows


def cmd_odds(args: argparse.Namespace) -> None:
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL / SUPABASE_SERVICE_KEY 가 필요합니다.")

    if args.on and len(str(args.on)) != 8:
        raise SystemExit("[odds] --on 은 YYYYMMDD 8자리여야 합니다.")

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    keys = _list_race_keys(
        client,
        meet=args.meet,
        since=args.since,
        until=args.until,
        on=args.on,
        max_races=args.max_races,
    )

    protected = set() if args.overwrite_prerace else _races_with_prerace_odds(client)
    if protected:
        before = len(keys)
        keys = [
            r
            for r in keys
            if (
                str(r.get("meet", "")),
                str(r.get("race_date", "")),
                _safe_int(r.get("race_no", 0), 0),
            )
            not in protected
        ]
        print(f"[odds] 사전 배당이 이미 있는 경주 {before - len(keys)}건 제외")

    print(
        f"[odds] 대상 경주: {len(keys)}건 (on={args.on}, since={args.since}, until={args.until}, meet={args.meet})"
    )

    total_ins = 0
    for i, r in enumerate(keys, start=1):
        meet = str(r.get("meet", ""))
        race_date = str(r.get("race_date", ""))
        race_no = _safe_int(r.get("race_no", 0), 0)
        if not meet or len(race_date) != 8 or race_no <= 0:
            continue

        try:
            items = fetch_odd_info_api5(meet, race_date, race_no)
        except Exception as e:
            print(f"[odds] KRA 실패 {meet} {race_date} R{race_no}: {e}")
            time.sleep(args.sleep)
            continue

        captured_at = datetime.now(timezone.utc).isoformat()
        rows_out: list[dict[str, Any]] = []
        seen: set[tuple] = set()
        for it in items:
            row = _item_row_for_race(meet, race_date, race_no, it, captured_at)
            if not row:
                continue
            key = (
                row["bet_type"],
                row["horse_no1"],
                row["horse_no2"],
                row["horse_no3"],
            )
            if key in seen:
                continue
            seen.add(key)
            rows_out.append(row)

        if args.dry_run:
            print(
                f"[odds] dry-run {i}/{len(keys)} {meet} {race_date} R{race_no} "
                f"→ {len(rows_out)}행 (원본 {len(items)}줄)"
            )
        else:
            if rows_out:
                for j in range(0, len(rows_out), 300):
                    batch = rows_out[j : j + 300]
                    res = client.table("odds").upsert(
                        batch,
                        on_conflict=(
                            "meet,race_date,race_no,bet_type,"
                            "horse_no1,horse_no2,horse_no3"
                        ),
                    ).execute()
                    total_ins += len(res.data) if res.data else len(batch)
            print(
                f"[odds] {i}/{len(keys)} {meet} {race_date} R{race_no} "
                f"upsert {len(rows_out)}행"
            )

        time.sleep(args.sleep)

    print(f"[odds] 완료. upsert 행(대략): {total_ins}")


def _default_params_path() -> str:
    return os.path.join(os.path.dirname(__file__), "models", "heuristic_tuned_params.json")


def cmd_predictions(args: argparse.Namespace) -> None:
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL / SUPABASE_SERVICE_KEY 가 필요합니다.")

    path = args.params_file or _default_params_path()
    with open(path, encoding="utf-8") as f:
        payload = json.load(f)
    if args.on and len(str(args.on)) != 8:
        raise SystemExit("[predictions] --on 은 YYYYMMDD 8자리여야 합니다.")

    best = payload.get("best_params", {})
    params = heuristic_params_from_dict(best, default_w_market=0.0)

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    samples = _build_race_dataset(
        client=client,
        meet=args.meet,
        since=args.since,
        max_races=args.max_races,
        until=args.until,
        on=args.on,
        include_unfinished=args.include_unfinished,
    )
    if not samples:
        print("[predictions] 샘플 경주가 없습니다.")
        return

    upcoming = sum(1 for s in samples if s.get("winner_no", 0) <= 0)
    print(
        f"[predictions] 경주 {len(samples)}건(결과 미확정 {upcoming}건), "
        f"model_version={args.model_version}, params={path}"
    )
    n = _sync_predictions(
        client, samples, params, model_version=args.model_version
    )
    print(f"[predictions] upsert 완료: {n}건")


def _race_accuracy(
    preds: list[dict[str, Any]], results: list[dict[str, Any]]
) -> dict[str, Any] | None:
    """저장된 예측 한 경주를 실제 결과와 대조한다. 정답이 없으면 None."""
    winner_no = next(
        (
            _safe_int(r.get("horse_no", 0))
            for r in results
            if _safe_int(r.get("rank", 0)) == 1
        ),
        0,
    )
    actual_top3 = {
        _safe_int(r.get("horse_no", 0))
        for r in results
        if 1 <= _safe_int(r.get("rank", 0)) <= PLACE_SLOTS
    }
    if winner_no <= 0 or not actual_top3 or not preds:
        return None

    win_ranked = sorted(preds, key=_win_order_key)
    place_ranked = sorted(preds, key=_place_order_key)
    pred_top3 = {p["horse_no"] for p in place_ranked[:PLACE_SLOTS]}

    denom = min(PLACE_SLOTS, len(actual_top3))
    brier = sum(
        ((p["place_probability"] / 100.0) - (1.0 if p["horse_no"] in actual_top3 else 0.0))
        ** 2
        for p in preds
    ) / len(preds)

    return {
        "field_size": len(preds),
        "top3_match": len(pred_top3 & actual_top3) / denom,
        "top3_winner": winner_no in pred_top3,
        "top1_hit": win_ranked[0]["horse_no"] == winner_no,
        "place_brier": brier,
    }


def cmd_accuracy(args: argparse.Namespace) -> None:
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL / SUPABASE_SERVICE_KEY 가 필요합니다.")
    if args.on and len(str(args.on)) != 8:
        raise SystemExit("[accuracy] --on 은 YYYYMMDD 8자리여야 합니다.")

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    predictions = _fetch_all_rows(
        client,
        "predictions",
        "meet,race_date,race_no,horse_no,win_probability,place_probability,model_version",
    )
    predictions = [
        p
        for p in predictions
        if str(p.get("model_version", "")) == args.model_version
    ]
    results = _fetch_all_rows(
        client, "race_results", "meet,race_date,race_no,horse_no,rank"
    )

    if args.meet:
        predictions = [p for p in predictions if str(p.get("meet", "")) == args.meet]
        results = [r for r in results if str(r.get("meet", "")) == args.meet]

    date_filter = {"since": args.since, "until": args.until, "on": args.on}
    predictions = _filter_by_race_date(predictions, **date_filter)
    results = _filter_by_race_date(results, **date_filter)

    preds_by_race: dict[tuple[str, str, int], list[dict[str, Any]]] = {}
    for row in predictions:
        key = (
            str(row.get("meet", "")),
            str(row.get("race_date", "")),
            _safe_int(row.get("race_no", 0)),
        )
        preds_by_race.setdefault(key, []).append(
            {
                "horse_no": _safe_int(row.get("horse_no", 0)),
                "win_probability": _safe_float(row.get("win_probability", 0.0)),
                "place_probability": _safe_float(row.get("place_probability", 0.0)),
            }
        )

    results_by_race: dict[tuple[str, str, int], list[dict[str, Any]]] = {}
    for row in results:
        key = (
            str(row.get("meet", "")),
            str(row.get("race_date", "")),
            _safe_int(row.get("race_no", 0)),
        )
        results_by_race.setdefault(key, []).append(row)

    rows_out: list[dict[str, Any]] = []
    for key in sorted(set(preds_by_race) & set(results_by_race)):
        metrics = _race_accuracy(preds_by_race[key], results_by_race[key])
        if metrics is None:
            continue
        meet, race_date, race_no = key
        rows_out.append(
            {
                "meet": meet,
                "race_date": race_date,
                "race_no": race_no,
                "model_version": args.model_version,
                "field_size": metrics["field_size"],
                "top3_match": round(metrics["top3_match"], 6),
                "top3_winner": metrics["top3_winner"],
                "top1_hit": metrics["top1_hit"],
                "place_brier": round(metrics["place_brier"], 6),
            }
        )

    if not rows_out:
        print(f"[accuracy] 평가 가능한 경주가 없습니다 (model={args.model_version}).")
        return

    races = len(rows_out)
    print(f"[accuracy] model={args.model_version} 경주 {races}건")
    print(
        "  top3_match={:.3f} top3_winner={:.3f} top1={:.3f} place_brier={:.4f}".format(
            sum(r["top3_match"] for r in rows_out) / races,
            sum(1 for r in rows_out if r["top3_winner"]) / races,
            sum(1 for r in rows_out if r["top1_hit"]) / races,
            sum(r["place_brier"] for r in rows_out) / races,
        )
    )

    if args.dry_run:
        print("[accuracy] dry-run: 업서트하지 않았습니다.")
        return

    upserted = 0
    for i in range(0, len(rows_out), 500):
        batch = rows_out[i : i + 500]
        res = (
            client.table("prediction_accuracy")
            .upsert(batch, on_conflict="meet,race_date,race_no,model_version")
            .execute()
        )
        upserted += len(res.data) if res.data else len(batch)
    print(f"[accuracy] prediction_accuracy 업서트 완료: {upserted}건")


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Supabase KRA/휴리스틱 동기화")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_odds = sub.add_parser("odds", help="KRA API5 배당 → Supabase odds")
    p_odds.add_argument("--meet", default=None, help="1/2/3")
    p_odds.add_argument(
        "--since", default=None, help="races.race_date >= since (on 미지정시)"
    )
    p_odds.add_argument(
        "--until", default=None, help="races.race_date <= until (on 미지정시)"
    )
    p_odds.add_argument(
        "--on", default=None, help="특정 시행일 YYYYMMDD만 (지정시 since/until 무시)"
    )
    p_odds.add_argument(
        "--max-races",
        type=int,
        default=500,
        help="races에서 처리할 최대 경주 수(0=제한없음, KRA 부하·금지에 유의)",
    )
    p_odds.add_argument(
        "--sleep", type=float, default=0.35, help="KRA 요청 간 대기(초)"
    )
    p_odds.add_argument(
        "--dry-run", action="store_true", help="삭제/삽입 없이 수집 개수만"
    )
    p_odds.add_argument(
        "--overwrite-prerace",
        action="store_true",
        help="이미 사전 배당이 저장된 경주도 다시 수집(기본값: 보존)",
    )
    p_odds.set_defaults(func=cmd_odds)

    p_pred = sub.add_parser("predictions", help="휴리스틱 predictions 테이블 업서트")
    p_pred.add_argument(
        "--params-file",
        default=None,
        help="heuristic_tuned_params.json 경로 (기본: backend/models/..)",
    )
    p_pred.add_argument("--meet", default=None)
    p_pred.add_argument("--since", default=None)
    p_pred.add_argument("--until", default=None)
    p_pred.add_argument(
        "--on", default=None, help="특정 시행일 YYYYMMDD만 (tune과 동일)"
    )
    p_pred.add_argument(
        "--max-races",
        type=int,
        default=MAX_TRAINING_RACES,
        help="0이면 _build_race_dataset 상한 없음",
    )
    p_pred.add_argument(
        "--model-version",
        default=MODEL_VERSION,
        help="predictions.model_version",
    )
    p_pred.add_argument(
        "--include-unfinished",
        action="store_true",
        help="결과가 아직 없는 앞으로의 경주도 예측을 생성해 업서트",
    )
    p_pred.set_defaults(func=cmd_predictions)

    p_acc = sub.add_parser(
        "accuracy", help="저장된 predictions 를 실제 결과와 대조해 적중률 기록"
    )
    p_acc.add_argument("--meet", default=None)
    p_acc.add_argument("--since", default=None)
    p_acc.add_argument("--until", default=None)
    p_acc.add_argument("--on", default=None, help="특정 시행일 YYYYMMDD만")
    p_acc.add_argument(
        "--model-version",
        default=MODEL_VERSION,
        help="평가할 predictions.model_version",
    )
    p_acc.add_argument(
        "--dry-run", action="store_true", help="업서트 없이 집계만 출력"
    )
    p_acc.set_defaults(func=cmd_accuracy)

    return p


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
