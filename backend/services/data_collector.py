import json
import os
from datetime import datetime, timedelta

import pandas as pd

from config import DATA_DIR
from services.kra_client import KraClient


class DataCollector:
    def __init__(self, client: KraClient) -> None:
        self.client = client
        os.makedirs(DATA_DIR, exist_ok=True)

    async def collect_race_results(
        self,
        meet: str,
        start_date: str,
        end_date: str,
    ) -> pd.DataFrame:
        """Collect race results for a date range and return as DataFrame."""
        all_results: list[dict] = []
        current = datetime.strptime(start_date, "%Y%m%d")
        end = datetime.strptime(end_date, "%Y%m%d")

        while current <= end:
            date_str = current.strftime("%Y%m%d")
            try:
                results = await self.client.get_race_result(meet=meet, rc_date=date_str)
                for r in results:
                    r["collect_date"] = date_str
                    r["meet"] = meet
                all_results.extend(results)
            except Exception:
                pass
            current += timedelta(days=1)

        df = pd.DataFrame(all_results)
        if not df.empty:
            path = os.path.join(DATA_DIR, f"results_{meet}_{start_date}_{end_date}.csv")
            df.to_csv(path, index=False, encoding="utf-8-sig")
        return df

    async def collect_start_lists(
        self,
        meet: str,
        rc_date: str,
    ) -> pd.DataFrame:
        """Collect entry data for a specific date."""
        entries = await self.client.get_start_list(meet=meet, rc_date=rc_date)
        df = pd.DataFrame(entries)
        if not df.empty:
            path = os.path.join(DATA_DIR, f"entries_{meet}_{rc_date}.csv")
            df.to_csv(path, index=False, encoding="utf-8-sig")
        return df

    async def collect_ai_results(
        self,
        meet: str,
        start_date: str,
        end_date: str,
    ) -> pd.DataFrame:
        """Collect AI-training race results with detailed fields."""
        all_results: list[dict] = []
        current = datetime.strptime(start_date, "%Y%m%d")
        end = datetime.strptime(end_date, "%Y%m%d")

        while current <= end:
            date_str = current.strftime("%Y%m%d")
            try:
                results = await self.client.get_ai_race_result(
                    rccrs_cd=meet, race_dt=date_str
                )
                all_results.extend(results)
            except Exception:
                pass
            current += timedelta(days=1)

        df = pd.DataFrame(all_results)
        if not df.empty:
            path = os.path.join(
                DATA_DIR, f"ai_results_{meet}_{start_date}_{end_date}.csv"
            )
            df.to_csv(path, index=False, encoding="utf-8-sig")
        return df

    def load_all_results(self) -> pd.DataFrame:
        """Load all cached CSV result files into a single DataFrame."""
        frames: list[pd.DataFrame] = []
        for f in os.listdir(DATA_DIR):
            if f.startswith("results_") and f.endswith(".csv"):
                path = os.path.join(DATA_DIR, f)
                frames.append(pd.read_csv(path))
        if frames:
            return pd.concat(frames, ignore_index=True)
        return pd.DataFrame()

    def load_all_ai_results(self) -> pd.DataFrame:
        frames: list[pd.DataFrame] = []
        for f in os.listdir(DATA_DIR):
            if f.startswith("ai_results_") and f.endswith(".csv"):
                path = os.path.join(DATA_DIR, f)
                frames.append(pd.read_csv(path))
        if frames:
            return pd.concat(frames, ignore_index=True)
        return pd.DataFrame()

    def load_seed_data(self) -> pd.DataFrame:
        path = os.path.join(DATA_DIR, "seed_training_data.csv")
        if os.path.exists(path):
            return pd.read_csv(path)
        return pd.DataFrame()
