import os
import json
from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional

from fastapi import FastAPI
from pydantic import BaseModel, Field, ConfigDict

from sqlalchemy import create_engine, Column, String, DateTime, Text
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://postgres:postgres@localhost:5432/healthos"
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

class IngestEvent(Base):
    __tablename__ = "ingest_events"
    id = Column(String, primary_key=True)  # event_id from client
    user_id = Column(String, nullable=False)
    source = Column(String, nullable=False)        # "healthkit" | "manual"
    schema_version = Column(String, nullable=False)
    event_type = Column(String, nullable=False)    # "healthkit_bundle"
    received_at = Column(DateTime(timezone=True), nullable=False)
    payload_json = Column(Text, nullable=False)

def init_db() -> None:
    Base.metadata.create_all(bind=engine)

class Source(str, Enum):
    healthkit = "healthkit"
    manual = "manual"

class WorkoutDTO(BaseModel):
    model_config = ConfigDict(extra="forbid")
    source_workout_id: str
    activity_type: str
    started_at: str
    ended_at: Optional[str] = None
    duration_sec: Optional[float] = None
    active_energy_kcal: Optional[float] = None
    distance_m: Optional[float] = None

class DailyMetricType(str, Enum):
    steps = "steps"
    active_energy_kcal = "active_energy_kcal"
    sleep_hours = "sleep_hours"
    body_weight_lbs = "body_weight_lbs"

class DailyMetricDTO(BaseModel):
    model_config = ConfigDict(extra="forbid")
    date: str  # YYYY-MM-DD
    metric_type: DailyMetricType
    value: float
    unit: str

class IngestPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: int = 1
    event_id: str = Field(..., description="UUID from client for idempotency")
    user_id: str = "matt"
    source: Source = Source.healthkit
    sent_at: str
    device_id: str

    workouts: List[WorkoutDTO] = []
    daily_metrics: List[DailyMetricDTO] = []

app = FastAPI()

@app.on_event("startup")
def _startup():
    init_db()

@app.get("/health")
def health():
    return {"ok": True, "ts": datetime.now(timezone.utc).isoformat()}

def _insert_event(payload: IngestPayload, event_type: str) -> None:
    db = SessionLocal()
    try:
        existing = db.get(IngestEvent, payload.event_id)
        if existing:
            return  # idempotent retry
        ev = IngestEvent(
            id=payload.event_id,
            user_id=payload.user_id,
            source=payload.source.value,
            schema_version=str(payload.schema_version),
            event_type=event_type,
            received_at=datetime.now(timezone.utc),
            payload_json=json.dumps(payload.model_dump()),
        )
        db.add(ev)
        db.commit()
    finally:
        db.close()

@app.post("/ingest/healthkit")
def ingest_healthkit(payload: IngestPayload):
    if payload.source != Source.healthkit:
        return {"status": "error", "message": "source must be healthkit"}
    _insert_event(payload, event_type="healthkit_bundle")
    return {
        "status": "ok",
        "stored_event_id": payload.event_id,
        "workouts": len(payload.workouts),
        "metrics": len(payload.daily_metrics),
    }
