#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load env if present
if [[ -f "$ROOT/.env" ]]; then
  set -a
  source "$ROOT/.env"
  set +a
fi

# Defaults
UVICORN_HOST="${UVICORN_HOST:-127.0.0.1}"
UVICORN_PORT="${UVICORN_PORT:-8000}"
DATABASE_URL="${DATABASE_URL:-postgresql+psycopg://postgres:postgres@127.0.0.1:5433/healthos}"

echo "==> Starting dependencies (postgres via docker compose)..."
cd "$ROOT"
docker compose up -d

echo "==> Ensuring Python venv exists..."
if [[ ! -d ".venv" ]]; then
  python3 -m venv .venv
fi

echo "==> Activating venv..."
source .venv/bin/activate

echo "==> Installing backend (editable) + dev deps..."
pip install -e ".[dev]" >/dev/null

echo "==> Running backend at http://${UVICORN_HOST}:${UVICORN_PORT}"
export DATABASE_URL
exec uvicorn healthos_backend.app:app --reload --host "$UVICORN_HOST" --port "$UVICORN_PORT"
