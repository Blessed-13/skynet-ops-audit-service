import sqlite3
import os
from app.config import DB_URL

def get_connection():
    os.makedirs(os.path.dirname(DB_URL), exist_ok=True) if "/" in DB_URL else None
    conn = sqlite3.connect(DB_URL)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_connection()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS events (
            eventId     TEXT PRIMARY KEY,
            type        TEXT NOT NULL,
            tenantId    TEXT NOT NULL,
            severity    TEXT NOT NULL,
            message     TEXT NOT NULL,
            source      TEXT NOT NULL,
            metadata    TEXT,
            occurredAt  TEXT,
            traceId     TEXT,
            storedAt    TEXT NOT NULL
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_tenant ON events(tenantId)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_severity ON events(severity)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_type ON events(type)")
    conn.commit()
    conn.close()