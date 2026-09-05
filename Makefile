.PHONY: up down logs build test test-gateway test-backend smoke-test clean

up:
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs -f

build:
	docker compose build

test-gateway:
	cd services/api-gateway && npm install && npm test

test-backend:
	cd services/task-service && pip install -r requirements-dev.txt && pytest -q

test: test-gateway test-backend

smoke-test:
	bash scripts/smoke-test.sh

clean:
	docker compose down -v
