import os
from dotenv import load_dotenv

load_dotenv()

KRA_SERVICE_KEY = os.getenv(
    "KRA_SERVICE_KEY",
    "788d1f62af9d665d2f002057f9526ac8f2776910fef87b0e95d27e232fe0967f",
)
KRA_BASE_URL = "https://apis.data.go.kr/B551015"

SUPABASE_URL = os.getenv(
    "SUPABASE_URL",
    "https://ymtctbpovnfbkrnmvtii.supabase.co",
)
SUPABASE_ANON_KEY = os.getenv(
    "SUPABASE_ANON_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InltdGN0YnBvdm5mYmtybm12dGlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ5MjczNTcsImV4cCI6MjA4MDUwMzM1N30.nFUb5GfUchT470X6IAGCrOFDlUe2Rcz3CIteE8_ar6c",
)

MEET_CODES = {"서울": "1", "제주": "2", "부산경남": "3"}
MEET_NAMES = {"1": "서울", "2": "제주", "3": "부산경남"}

MODEL_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "models")
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")

os.makedirs(MODEL_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)
