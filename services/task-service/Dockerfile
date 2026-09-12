# --- Build stage: resolve dependencies into an isolated prefix ---
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# --- Runtime stage: small image, no build toolchain, non-root user ---
FROM python:3.12-slim

# Explicit numeric UID/GID - see services/api-gateway/Dockerfile's
# identical comment for why this matters (Kubernetes' runAsNonRoot check
# needs a UID it can verify statically, not just a named user). Kept in
# sync with helm/taskflow's securityContext.pod.runAsUser (values.yaml),
# and using 10001 (not 1000) for the same reason as
# services/api-gateway/Dockerfile: keeping both images' UID consistent.
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --create-home app

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
