import os
from dotenv import load_dotenv

load_dotenv()

KRA_SERVICE_KEY = os.getenv("KRA_SERVICE_KEY", "")
KRA_BASE_URL = os.getenv("KRA_BASE_URL", "https://apis.data.go.kr/B551015")

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")

MODEL_DIR = os.path.join(os.path.dirname(__file__), "models")
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
