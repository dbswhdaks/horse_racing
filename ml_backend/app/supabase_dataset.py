"""Supabase 운영 데이터를 누출 없는 ML 학습 CSV로 내보냅니다."""

from __future__ import annotations

import argparse
import os

import pandas as pd

from app.config import DATA_DIR
from app.supabase_client import get_client


def _fetch_all(table: str, columns: str, batch_size: int = 1000) -> list[dict]:
    client = get_client()
    rows: list[dict] = []
    offset = 0
    while True:
        response = (
            client.table(table)
            .select(columns)
            .range(offset, offset + batch_size - 1)
            .execute()
        )
        chunk = response.data or []
        rows.extend(chunk)
        if len(chunk) < batch_size:
            return rows
        offset += batch_size


def export_training_csv(
    output_path: str | None = None,
    *,
    since: str | None = None,
) -> str:
    entries = pd.DataFrame(
        _fetch_all(
            "race_entries",
            (
                "meet,race_date,race_no,horse_no,horse_name,birth_place,sex,"
                "age,jockey_name,trainer_name,weight,rating,total_prize,"
                "recent_prize,win_count,place_count,total_races,horse_weight"
            ),
        )
    )
    results = pd.DataFrame(
        _fetch_all(
            "race_results",
            (
                "meet,race_date,race_no,horse_no,rank,race_time,s1f,g3f,"
                "distance"
            ),
        )
    )
    races = pd.DataFrame(
        _fetch_all("races", "meet,race_date,race_no,distance")
    )
    if entries.empty or results.empty:
        raise RuntimeError("학습 가능한 race_entries/race_results 데이터가 없습니다.")

    for frame in (entries, results, races):
        frame["race_date"] = frame["race_date"].astype(str)
        if since:
            frame.drop(frame[frame["race_date"] < since].index, inplace=True)

    keys = ["meet", "race_date", "race_no", "horse_no"]
    dataset = entries.merge(
        results,
        on=keys,
        how="inner",
        suffixes=("", "_result"),
        validate="one_to_one",
    )
    dataset = dataset.merge(
        races.rename(columns={"distance": "race_distance"}),
        on=["meet", "race_date", "race_no"],
        how="left",
        validate="many_to_one",
    )
    dataset["race_distance"] = dataset["race_distance"].fillna(
        dataset.get("distance", 0)
    )
    dataset.rename(columns={"weight": "burden_weight"}, inplace=True)
    dataset.drop(columns=["distance"], inplace=True, errors="ignore")

    # 확정 배당은 의도적으로 내보내지 않습니다.
    output_path = output_path or os.path.join(DATA_DIR, "race_data.csv")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    dataset.sort_values(
        ["race_date", "meet", "race_no", "horse_no"]
    ).to_csv(output_path, index=False, encoding="utf-8-sig")
    print(
        f"[DATASET] {dataset[['meet', 'race_date', 'race_no']].drop_duplicates().shape[0]}"
        f"경주 / {len(dataset)}행 저장: {output_path}"
    )
    return output_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Supabase → ML 학습 CSV")
    parser.add_argument("--output", default=None)
    parser.add_argument("--since", default=None, help="YYYYMMDD")
    args = parser.parse_args()
    export_training_csv(args.output, since=args.since)
