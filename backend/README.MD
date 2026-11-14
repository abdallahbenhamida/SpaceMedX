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

## Core Modules & API Endpoints

All endpoints are versioned under `/api/v1`. Interactive Swagger documentation is available at `/docs` and ReDoc at `/redoc`.

### 1. Authentication (`/api/v1/auth`)
Handles user registration, identity creation, and credential validation.
- **`POST /api/v1/auth/register`**
  - **Payload:** `UserCreate` (email, password [min length 8], full_name, role)
  - **Response (`201 Created`):** `UserResponse` (id, email, full_name, role, status, is_verified)
  - **Description:** Registers a new crew member or system user with hashed passwords (bcrypt).
- **`POST /api/v1/auth/login`**
  - **Payload:** `LoginRequest` (email, password)
  - **Response (`200 OK`):** `Token` (access_token, token_type: "bearer")
  - **Description:** Authenticates user credentials and issues a signed JWT access token containing subject ID and role claims.

### 2. User Profiles (`/api/v1/users`)
Manages account identity and profile retrieval.
- **`GET /api/v1/users/me`**
  - **Auth Required:** Bearer Token (`get_current_user`)
  - **Response (`200 OK`):** `UserResponse`
  - **Description:** Retrieves the profile information of the currently authenticated user.

### 3. Medical Telemetry & Records (`/api/v1/medical`)
Monitors and logs crew health metrics, vitals, and clinical assessments.
- **`POST /api/v1/medical/records`**
  - **Auth Required:** Bearer Token (Restricted strictly to `medical_officer` role)
  - **Payload:** `MedicalRecordCreate` (user_id, heart_rate, blood_pressure_systolic, blood_pressure_diastolic, oxygen_saturation, body_temperature, notes)
  - **Response (`201 Created`):** `MedicalRecordResponse`
  - **Description:** Logs a new health telemetry entry for a crew member. Validates clinical boundaries for vitals (heart rate, blood pressure, SpO2, and temperature).
- **`GET /api/v1/medical/records/{user_id}`**
  - **Auth Required:** Bearer Token (Accessible by the user themselves or a `medical_officer`)
  - **Response (`200 OK`):** List of `MedicalRecordResponse` objects
  - **Description:** Retrieves historical medical records for a specific crew member sorted in reverse chronological order.

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
    SELECT * FROM users;
    SELECT * FROM medical_records;
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

To maintain strict type safety and a clean architecture across modules, SpaceMedx uses centralized enumerations located in `app/enums/`:

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