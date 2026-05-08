.PHONY: help dev up down logs migrate shell-api shell-db test lint format clean backup

COMPOSE = docker compose
BACKEND = $(COMPOSE) exec api
FRONTEND = $(COMPOSE) exec frontend

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Development ───────────────────────────────────────────────────────────────
dev: ## Start all services in development mode
	$(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml up --build -d

dev-backend: ## Run backend in dev mode (hot reload)
	cd backend && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

dev-frontend: ## Run frontend in dev mode
	cd frontend && npm run dev

dev-worker: ## Run Celery worker in dev mode
	cd backend && celery -A app.workers.celery_app worker --loglevel=info -Q collectors,alerts,notifications,discovery,default

dev-beat: ## Run Celery beat in dev mode
	cd backend && celery -A app.workers.celery_app beat --loglevel=info --scheduler=redbeat.RedBeatScheduler

# ── Docker ────────────────────────────────────────────────────────────────────
up: ## Start production stack
	$(COMPOSE) up -d --build

down: ## Stop all services
	$(COMPOSE) down

restart: ## Restart all services
	$(COMPOSE) restart

logs: ## Tail all logs
	$(COMPOSE) logs -f

logs-api: ## Tail API logs
	$(COMPOSE) logs -f api

logs-worker: ## Tail worker logs
	$(COMPOSE) logs -f worker

ps: ## Show running containers
	$(COMPOSE) ps

# ── Database ──────────────────────────────────────────────────────────────────
migrate: ## Run Alembic migrations
	$(COMPOSE) run --rm migrate alembic upgrade head

migrate-down: ## Rollback last migration
	$(BACKEND) alembic downgrade -1

migrate-history: ## Show migration history
	$(BACKEND) alembic history --verbose

shell-db: ## Open psql shell
	$(COMPOSE) exec db psql -U corepulse -d corepulse

# ── Dev tools ─────────────────────────────────────────────────────────────────
shell-api: ## Shell into API container
	$(BACKEND) bash

test: ## Run all tests
	$(BACKEND) pytest tests/ -v

test-backend: ## Run backend tests with coverage
	cd backend && pytest tests/ -v --cov=app --cov-report=term-missing

lint: ## Lint backend code
	cd backend && ruff check app/ && mypy app/

format: ## Format backend code
	cd backend && ruff format app/ && isort app/

type-check: ## Frontend type check
	cd frontend && npm run type-check

# ── Secrets & SSL ─────────────────────────────────────────────────────────────
gen-secret: ## Generate SECRET_KEY
	@openssl rand -hex 32

gen-ssl: ## Generate self-signed SSL certificate
	mkdir -p deployments/ssl
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout deployments/ssl/key.pem \
		-out deployments/ssl/cert.pem \
		-subj "/C=US/ST=Local/L=Local/O=CorePulse/CN=localhost"

# ── Backup & Restore ──────────────────────────────────────────────────────────
backup: ## Backup database
	./scripts/backup.sh

restore: ## Restore database (usage: make restore FILE=backup.sql.gz)
	./scripts/restore.sh $(FILE)

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean: ## Remove containers, volumes, images
	$(COMPOSE) down -v --remove-orphans
	docker system prune -f

clean-all: ## Nuclear option — remove everything
	$(COMPOSE) down -v --remove-orphans --rmi all
	docker volume prune -f
	docker system prune -af

# ── Initial setup ─────────────────────────────────────────────────────────────
setup: ## First-time setup: copy env, generate ssl, migrate
	@cp -n .env.example .env || true
	@$(MAKE) gen-ssl
	@$(MAKE) up
	@sleep 10
	@$(MAKE) migrate
	@echo "\n✅ CorePulse is ready at https://localhost"
	@echo "   Default credentials: admin / corepulse"
