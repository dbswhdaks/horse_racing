#!/usr/bin/env bash
# 로컬/서버 cron용: KRA 배당 백필 + 휴리스틱 predictions 동기화
# 사용: 환경변수 SUPABASE_URL, SUPABASE_SERVICE_KEY, KRA_SERVICE_KEY
#       (선택) SINCE=YYYYMMDD — 기본: 14일 전
# crontab 예: 0 10 * * * cd /path/to/horse_racing && ./scripts/scheduled_ops.sh >>/var/log/horse_racing_ops.log 2>&1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT/.env"
  set +a
fi
if [[ -f "$ROOT/backend/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT/backend/.env"
  set +a
fi
: "${SINCE:=$(date -d "14 days ago" +%Y%m%d 2>/dev/null || date -v-14d +%Y%m%d 2>/dev/null)}"
echo "[$(date -Iseconds)] scheduled_ops SINCE=$SINCE"
export PYTHONPATH="${ROOT}/backend${PYTHONPATH:+:$PYTHONPATH}"
python backend/ops_sync.py odds --since "$SINCE" --max-races 400 --sleep 0.35
python backend/ops_sync.py predictions --since "$SINCE" --max-races 800 --model-version heuristic-place-1.1
echo "[$(date -Iseconds)] scheduled_ops done"
