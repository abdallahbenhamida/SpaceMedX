.PHONY: help up down build logs ps clean restart health

# Default target when running just 'make'
help:
	@echo "SpaceMedx Docker Management Commands:"
	@echo "  make up       - Create, build, and start all containers in detached mode"
	@echo "  make down     - Stop and remove running containers"
	@echo "  make build    - Rebuild container images from scratch (no cache)"
	@echo "  make logs     - Tail logs from all containers"
	@echo "  make ps       - Show status of running containers"
	@echo "  make clean    - Stop containers AND delete database volumes (DESTRUCTIVE)"
	@echo "  make restart  - Restart all backend and proxy services"
	@echo "  make health   - Check API health endpoint"

up:
	@if [ ! -f .env ]; then cp env.example .env; echo "Created .env from env.example"; fi
	docker compose up -d --build

down:
	docker compose down

build:
	docker compose build --no-cache

logs:
	docker compose logs -f

ps:
	docker compose ps

clean:
	docker compose down -v --rmi local --remove-orphans

restart:
	docker compose restart

health:
	curl -f http://localhost/health || echo "API is not responding yet."
