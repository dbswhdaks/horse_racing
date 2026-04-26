#!/usr/bin/env bash
# 휴리스틱 튜닝(주간·수동) — operations/data가 Supabase에 있어야 함
# env: SUPABASE_URL, SUPABASE_SERVICE_KEY
#   TUNE_TRIALS (default 500), TUNE_MAX_RACES (default 800), TUNE_SINCE (optional yyyymmdd)
#   TUNE_AUTO_SYNC=1 이면 튜닝 뒤 predictions 테이블까지 upsert
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
export PYTHONPATH="${ROOT}/backend${PYTHONPATH:+:$PYTHONPATH}"
TUNE_TRIALS="${TUNE_TRIALS:-500}"
TUNE_MAX_RACES="${TUNE_MAX_RACES:-800}"
OUT=backend/models/heuristic_tuned_params.json
args=(python backend/tune_heuristic_predictions.py --trials "$TUNE_TRIALS" --max-races "$TUNE_MAX_RACES" --output "$OUT")
if [[ -n "${TUNE_SINCE:-}" ]]; then
  args+=("--since" "$TUNE_SINCE")
fi
if [[ "${TUNE_AUTO_SYNC:-0}" == "1" ]]; then
  args+=("--sync-predictions" "--model-version" "heuristic-place-1.1")
fi
echo "Running: ${args[*]}"
exec "${args[@]}"
