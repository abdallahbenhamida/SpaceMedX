# SpaceMedx Backend

Long-duration space mission health monitoring platform backend built with **Python 3.12+**, **FastAPI**, **SQLAlchemy 2.0 (Async)**, **PostgreSQL 18 Alpine**, and **Docker**.

---

## Tech Stack & Architecture
- **Framework:** FastAPI
- **ORM:** SQLAlchemy 2.0+ (Async with Greenlet)
- **Database:** PostgreSQL 18 Alpine
- **Migrations:** Alembic (Automated via container entrypoint script)
- **Validation:** Pydantic v2
- **Authentication:** Passlib (Bcrypt) & PyJWT
- **Testing:** Pytest (`pytest-asyncio`, `httpx`, AnyIO, Pytest-cov)

---

## Setup & Installation

1. **Configure Environment Variables:**
   ```bash
   cp env.example .env
   ```
   *Generate a secure `SECRET_KEY`:*
   ```bash
   openssl rand -hex 32
   # OR using Python
   python3 -c "import secrets; print(secrets.token_hex(32))"
   ```

2. **Build and Run the Container Stack:**
   ```bash
   make build
   make up
   ```
   *(Database migrations run automatically on container startup via the entrypoint script.)*

---

## Database & Migrations

To manage database schema revisions and inspect records:

- **Generate a new migration (auto-generated from models):**
  ```bash
  docker exec -it spacemedx-api alembic revision --autogenerate -m "description of changes"
  ```

- **Apply pending migrations:**
  ```bash
  docker exec -it spacemedx-api alembic upgrade head
  ```

- **Connect to PostgreSQL database interactively:**
  ```bash
  docker exec -it spacemedx-db psql -U spacemedx_user -d spacemedx
  ```
  * Inside `psql`:
    ```sql
    \dt          -- List all tables
    \dt+         -- Detailed table view
    SELECT * FROM users;
    ```

---

## Testing

The backend uses an asynchronous testing suite powered by `pytest` and `httpx`:

- **Run all backend tests inside Docker:**
  ```bash
  docker exec -it spacemedx-api pytest
  ```
- **Run with verbose output:**
  ```bash
  docker exec -it spacemedx-api pytest -v
  ```

---

## Using Makefile (`make`)

The project includes a convenient Makefile for container orchestration:

- **`make help`** — List all available make commands
- **`make up`** — Start all Docker containers
- **`make down`** — Stop and remove Docker containers
- **`make build`** — Build or rebuild container images
- **`make logs`** — View container logs
- **`make ps`** — List running containers
- **`make clean`** — Remove containers, networks, and volumes
- **`make restart`** — Restart the service stack
- **`make health`** — Check container health status

---

## Domain Vocabulary (Enums Reference)

To maintain strict type safety and a clean architecture across modules, SpaceMedx uses centralized enumerations located in `backend/app/enums/`:

### 1. User, Identity (`app.enums.user`)
- **`UserRole`**:
  - `system_admin`, `org_admin`, `mission_admin`, `team_leader`, `astronaut`, `medical_officer`, `researcher`, `mission_control`, `guest_viewer`
- **`AccountStatus`**:
  - `active` — Fully operational account
  - `invited` — Pending registration/activation
  - `suspended` — Temporarily disabled
  - `deactivated` — Permanently disabled
  - `offline` — Local habitat caching / disconnected space-flight operations mode

### 2. Telemetry, Observations (`app.enums.observation`)
- **`ObservationQuality`**:
  - `Valid`, `Questionable`, `Invalid`, `Missing`
- **`ObservationSource`**:
  - `Simulator`, `Wearable`, `Manual`, `Medical Device`

### 3. Emergency Protocols (`app.enums.emergency`)
- **`EmergencyGrantStatus`**:
  - `active`, `expired`, `revoked`

### 4. Audit, Compliance (`app.enums.audit`)
- **`AuditAction`**:
  - `READ`, `CREATE`, `UPDATE`, `DELETE`, `SHARE`, `EXPORT`, `EMERGENCY_GRANT`, `EMERGENCY_REVOKE`
