"""Supabase predictions 테이블의 model_version을 heuristic-2.0으로 업데이트"""

from supabase import create_client
from dotenv import load_dotenv
import os

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

supa = create_client(SUPABASE_URL, SUPABASE_KEY)

def main():
    result = (
        supa.table("predictions")
        .update({"model_version": "heuristic-2.0"})
        .eq("model_version", "heuristic-1.0")
        .execute()
    )
    
    updated_count = len(result.data) if result.data else 0
    print(f"업데이트 완료: {updated_count}건")
    
    verify = (
        supa.table("predictions")
        .select("model_version")
        .limit(5)
        .execute()
    )
    print("확인:", [r["model_version"] for r in verify.data])


if __name__ == "__main__":
    main()
