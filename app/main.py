import time
import json
import logging
import asyncio
from datetime import datetime, timezone
from typing import Optional, Any
from contextlib import asynccontextmanager

import uuid
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, field_validator, model_validator

from app.config import (
    SERVICE_NAME, APP_ENV, LOG_LEVEL,
    METRICS_DEMO_ENABLED, MAX_EVENTS_LIMIT, API_KEY
)
from app.database import init_db, get_connection

# ---------------------------------------------------------------------------
# Structured JSON logger
# ---------------------------------------------------------------------------
logging.basicConfig(level=LOG_LEVEL.upper())
logger = logging.getLogger(SERVICE_NAME)

def log(level: str, msg: str, **kwargs):
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": level,
        "service": SERVICE_NAME,
        "env": APP_ENV,
        "message": msg,
        **kwargs
    }
    print(json.dumps(entry))


# ---------------------------------------------------------------------------
# Lifespan — init DB on startup
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    log("info", "Service started", port=8000, store="sqlite")
    yield
    log("info", "Service shutting down")


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(
    title=SERVICE_NAME,
    version="1.0.0",
    description="AIRMAN Skynet Ops Audit Service",
    lifespan=lifespan
)

VALID_SEVERITIES = {"info", "warning", "error", "critical"}


# ---------------------------------------------------------------------------
# Request logging middleware
# ---------------------------------------------------------------------------
@app.middleware("http")
async def request_logger(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration_ms = round((time.time() - start) * 1000, 2)
    log("info", "request", method=request.method, path=request.url.path,
        status=response.status_code, duration_ms=duration_ms)
    return response


# ---------------------------------------------------------------------------
# Optional API key auth middleware
# ---------------------------------------------------------------------------
@app.middleware("http")
async def api_key_guard(request: Request, call_next):
    if API_KEY and request.url.path not in ("/health", "/docs", "/openapi.json"):
        key = request.headers.get("X-API-Key")
        if key != API_KEY:
            return JSONResponse(status_code=401, content={"error": "Unauthorized"})
    return await call_next(request)


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------
class EventIn(BaseModel):
    type: str
    tenantId: str
    severity: str
    message: str
    source: str
    metadata: Optional[dict[str, Any]] = None
    occurredAt: Optional[str] = None
    traceId: Optional[str] = None

    @field_validator("tenantId", "message")
    @classmethod
    def must_not_be_empty(cls, v):
        if not v or not v.strip():
            raise ValueError("must not be empty")
        return v

    @field_validator("severity")
    @classmethod
    def valid_severity(cls, v):
        if v not in VALID_SEVERITIES:
            raise ValueError(f"must be one of: {', '.join(VALID_SEVERITIES)}")
        return v


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": SERVICE_NAME,
        "environment": APP_ENV,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


@app.post("/events", status_code=201)
def post_event(event: EventIn):
    event_id = "evt_" + uuid.uuid4().hex
    stored_at = datetime.now(timezone.utc).isoformat()

    conn = get_connection()
    try:
        conn.execute("""
            INSERT INTO events
              (eventId, type, tenantId, severity, message, source,
               metadata, occurredAt, traceId, storedAt)
            VALUES (?,?,?,?,?,?,?,?,?,?)
        """, (
            event_id,
            event.type,
            event.tenantId,
            event.severity,
            event.message,
            event.source,
            json.dumps(event.metadata) if event.metadata else None,
            event.occurredAt,
            event.traceId,
            stored_at
        ))
        conn.commit()
    finally:
        conn.close()

    log("info", "event_stored", eventId=event_id, type=event.type,
        tenantId=event.tenantId, severity=event.severity)

    return {"success": True, "eventId": event_id, "storedAt": stored_at}


@app.get("/events")
def get_events(
    tenantId: Optional[str] = Query(None),
    severity:  Optional[str] = Query(None),
    type:      Optional[str] = Query(None),
    limit:     int = Query(20, ge=1, le=MAX_EVENTS_LIMIT),
    offset:    int = Query(0, ge=0),
):
    if severity and severity not in VALID_SEVERITIES:
        raise HTTPException(400, f"severity must be one of: {', '.join(VALID_SEVERITIES)}")

    filters, params = [], []
    if tenantId:
        filters.append("tenantId = ?"); params.append(tenantId)
    if severity:
        filters.append("severity = ?");  params.append(severity)
    if type:
        filters.append("type = ?");      params.append(type)

    where = ("WHERE " + " AND ".join(filters)) if filters else ""

    conn = get_connection()
    try:
        total = conn.execute(f"SELECT COUNT(*) FROM events {where}", params).fetchone()[0]
        rows  = conn.execute(
            f"SELECT * FROM events {where} ORDER BY storedAt DESC LIMIT ? OFFSET ?",
            params + [limit, offset]
        ).fetchall()
    finally:
        conn.close()

    items = []
    for r in rows:
        item = dict(r)
        if item.get("metadata"):
            item["metadata"] = json.loads(item["metadata"])
        items.append(item)

    return {"items": items, "total": total, "limit": limit, "offset": offset}


@app.get("/metrics-demo")
async def metrics_demo(mode: Optional[str] = Query(None)):
    if not METRICS_DEMO_ENABLED:
        raise HTTPException(404, "metrics-demo is disabled")

    if mode == "error":
        log("error", "metrics_demo_error_triggered")
        raise HTTPException(500, "Simulated server error")

    if mode == "slow":
        log("info", "metrics_demo_slow_triggered", sleep_sec=2)
        await asyncio.sleep(2)
        return {"status": "slow response completed", "sleptSeconds": 2}

    if mode == "burst":
        for i in range(10):
            log("info", f"metrics_demo_burst_log_{i}", iteration=i)
        return {"status": "burst logs emitted", "count": 10}

    return {"status": "ok", "mode": "default", "service": SERVICE_NAME}