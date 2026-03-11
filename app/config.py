import os

SERVICE_NAME = os.getenv("SERVICE_NAME", "skynet-ops-audit-service")
APP_ENV = os.getenv("APP_ENV", "dev")
PORT = int(os.getenv("PORT", 8000))
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")
STORE_BACKEND = os.getenv("STORE_BACKEND", "sqlite")
DB_URL = os.getenv("DB_URL", "./data/events.db")
METRICS_DEMO_ENABLED = os.getenv("METRICS_DEMO_ENABLED", "true").lower() == "true"
MAX_EVENTS_LIMIT = int(os.getenv("MAX_EVENTS_LIMIT", 100))
API_KEY = os.getenv("API_KEY", None)  # Optional simple auth