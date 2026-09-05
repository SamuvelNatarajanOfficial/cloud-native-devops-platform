import logging
import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import Base, SessionLocal, engine, get_db
from app.models import Task
from app.schemas import TaskCreate, TaskOut, TaskUpdate

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper())
logger = logging.getLogger("task-service")

REQUEST_COUNT = Counter("task_service_requests_total", "Total requests handled", ["endpoint"])


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Phase 1 keeps schema management simple; a later phase introduces
    # Alembic migrations instead of create_all.
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title="task-service", version="0.1.0", lifespan=lifespan)


@app.get("/health")
def health():
    """Liveness probe: process is up and serving requests."""
    REQUEST_COUNT.labels(endpoint="/health").inc()
    return {"status": "ok"}


@app.get("/ready")
def ready():
    """Readiness probe: confirms the database connection is usable."""
    REQUEST_COUNT.labels(endpoint="/ready").inc()
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
