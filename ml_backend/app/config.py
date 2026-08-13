import os
from dotenv import load_dotenv

load_dotenv()

KRA_SERVICE_KEY = os.getenv("KRA_SERVICE_KEY", "")
KRA_BASE_URL = "https://apis.data.go.kr/B551015"

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")

MEET_CODES = {"서울": "1", "제주": "2", "부산경남": "3"}
MEET_NAMES = {"1": "서울", "2": "제주", "3": "부산경남"}

MODEL_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "models")
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")

os.makedirs(MODEL_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)
