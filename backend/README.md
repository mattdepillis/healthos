# HealthOS Backend

## Setup
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"

## Run (Postgres expected)
export DATABASE_URL="postgresql+psycopg://postgres:postgres@localhost:5432/healthos"
uvicorn healthos_backend.app:app --reload --port 8000

## Test
pytest -q
