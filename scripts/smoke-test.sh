#!/usr/bin/env bash
# Basic end-to-end smoke test against a running docker-compose stack.
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"

echo "Checking gateway health..."
curl -sf "${GATEWAY_URL}/health" > /dev/null

echo "Checking gateway readiness (upstream reachable)..."
curl -sf "${GATEWAY_URL}/ready" > /dev/null

echo "Creating a task through the gateway..."
CREATE_RESPONSE=$(curl -sf -X POST "${GATEWAY_URL}/api/tasks" \
  -H "Content-Type: application/json" \
  -d '{"title":"Smoke test task"}')
echo "Created: ${CREATE_RESPONSE}"

echo "Listing tasks through the gateway..."
curl -sf "${GATEWAY_URL}/api/tasks" > /dev/null

echo "Smoke test passed."
