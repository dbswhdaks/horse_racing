import os
from dotenv import load_dotenv

load_dotenv()

KRA_SERVICE_KEY = os.getenv(
    "KRA_SERVICE_KEY",
    "788d1f62af9d665d2f002057f9526ac8f2776910fef87b0e95d27e232fe0967f",
)
KRA_BASE_URL = os.getenv("KRA_BASE_URL", "https://apis.data.go.kr/B551015")

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")

MODEL_DIR = os.path.join(os.path.dirname(__file__), "models")
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
