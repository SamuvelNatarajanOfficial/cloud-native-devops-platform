# --- Build stage: resolve dependencies into an isolated prefix ---
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# --- Runtime stage: small image, no build toolchain, non-root user ---
FROM python:3.12-slim

RUN groupadd --system app && useradd --system --gid app --create-home app

WORKDIR /app

COPY --from=builder /root/.local /home/app/.local
COPY app ./app

RUN chown -R app:app /app /home/app/.local

ENV PATH=/home/app/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER app

EXPOSE 8000

# hadolint ignore=DL3025
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=2)" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
