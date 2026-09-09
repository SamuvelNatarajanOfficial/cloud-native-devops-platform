import logging
import os
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import Base, SessionLocal, engine, get_db
from app.models import Task
from app.schemas import TaskCreate, TaskOut, TaskUpdate

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper())
logger = logging.getLogger("task-service")

# Golden-signal HTTP metrics for every route (traffic, errors, latency - see
# docs/observability-architecture.md#golden-signals). Labeled by the ROUTE
# TEMPLATE (e.g. "/tasks/{task_id}"), never the resolved path - using the
# resolved path would put one Prometheus time series per task UUID ever
# requested, an unbounded-cardinality label that would eventually make
# Prometheus fall over. See observability/README.md#cardinality.
HTTP_REQUESTS_TOTAL = Counter(
    "task_service_http_requests_total",
    "Total HTTP requests, labeled by method, route template, and status code",
    ["method", "path", "status_code"],
)
HTTP_REQUEST_DURATION_SECONDS = Histogram(
    "task_service_http_request_duration_seconds",
    "HTTP request duration in seconds, labeled by method and route template",
    ["method", "path"],
)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Phase 1 keeps schema management simple; a later phase introduces
    # Alembic migrations instead of create_all.
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title="task-service", version="0.1.0", lifespan=lifespan)


@app.middleware("http")
async def record_request_metrics(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start

    # request.scope["route"] is set by Starlette's router once the request
    # has been matched, which has already happened by the time call_next()
    # returns - so this is the template ("/tasks/{task_id}"), not the raw
    # path. A request that matched no route at all (a genuine 404 on an
    # unknown path) falls back to a fixed "unmatched" label instead of the
    # raw path, for the same cardinality reason described above.
    route = request.scope.get("route")
    path = route.path if route is not None else "unmatched"

    HTTP_REQUESTS_TOTAL.labels(method=request.method, path=path, status_code=response.status_code).inc()
    HTTP_REQUEST_DURATION_SECONDS.labels(method=request.method, path=path).observe(duration)
    return response


@app.get("/health")
def health():
    """Liveness probe: process is up and serving requests."""
    return {"status": "ok"}


@app.get("/ready")
def ready():
    """Readiness probe: confirms the database connection is usable."""
    try:
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        db.close()
    except Exception as exc:  # noqa: BLE001 - surface any DB failure as not-ready
        logger.warning("readiness check failed: %s", exc)
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/tasks", response_model=TaskOut, status_code=201)
def create_task(payload: TaskCreate, db: Session = Depends(get_db)):
    task = Task(title=payload.title, description=payload.description or "")
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


@app.get("/tasks", response_model=list[TaskOut])
def list_tasks(db: Session = Depends(get_db)):
    return db.query(Task).order_by(Task.created_at.desc()).all()


@app.get("/tasks/{task_id}", response_model=TaskOut)
def get_task(task_id: str, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    return task


@app.patch("/tasks/{task_id}", response_model=TaskOut)
def update_task(task_id: str, payload: TaskUpdate, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")

    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(task, field, value)

    db.commit()
    db.refresh(task)
    return task


@app.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: str, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    db.delete(task)
    db.commit()
