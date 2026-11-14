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

### 4. Habitat & Environmental Telemetry (`/api/v1/environment`)
Tracks atmospheric composition, radiation exposure, and environmental conditions across space missions and surface bases.
- **`POST /api/v1/environment/telemetry`**
  - **Auth Required:** Bearer Token (Restricted to `medical_officer`, `mission_control`, `mission_admin`, `org_admin`, or `sys_admin`)
  - **Payload:** `EnvironmentalTelemetryCreate` (location_type, location_identifier, metric_type, value, unit, alert_level, notes)
  - **Response (`201 Created`):** `EnvironmentalTelemetryResponse`
  - **Description:** Ingests real-time environmental sensor readings and alert levels for a habitat, spacecraft, or planetary outpost.
- **`GET /api/v1/environment/telemetry`**
  - **Auth Required:** Bearer Token (`get_current_user`)
  - **Query Parameters:** `location_type` (optional), `location_identifier` (optional), `limit` (default: 50)
  - **Response (`200 OK`):** List of `EnvironmentalTelemetryResponse` objects
  - **Description:** Queries historical and active environmental telemetry filtered by location type or base identifier.

### 5. Emergency Protocols & Override Grants (`/api/v1/emergency`)
Manages time-bound emergency access overrides and automatically logs compliance audit trails (`AuditLog`) for space agency oversight.
- **`POST /api/v1/emergency/grants`**
  - **Auth Required:** Bearer Token (Restricted to `medical_officer`, `mission_admin`, `sys_admin`, or `org_admin`)
  - **Payload:** `EmergencyGrantCreate` (grantee_id, reason [5–500 chars], duration_hours [default: 4, range: 1–72])
  - **Response (`201 Created`):** `EmergencyGrantResponse` (id, grantor_id, grantee_id, reason, status, expires_at, created_at)
  - **Description:** Issues a temporary emergency access override grant to a crew member or operator and records an `EMERGENCY_GRANT` audit log entry.
- **`GET /api/v1/emergency/grants`**
  - **Auth Required:** Bearer Token (Restricted to `medical_officer`, `mission_admin`, `sys_admin`, `org_admin`, or `mission_control`)
  - **Response (`200 OK`):** List of `EmergencyGrantResponse` objects
  - **Description:** Retrieves all issued emergency access grants ordered by creation timestamp descending.
- **`PATCH /api/v1/emergency/grants/{grant_id}/revoke`**
  - **Auth Required:** Bearer Token (Restricted to `medical_officer`, `mission_admin`, `sys_admin`, or `org_admin`)
  - **Response (`200 OK`):** `EmergencyGrantResponse` (with `status: "revoked"`)
  - **Description:** Immediately revokes an active emergency access grant prior to expiration and records an `EMERGENCY_REVOKE` audit log entry.

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
    SELECT * FROM environmental_telemetry;
    SELECT * FROM emergency_access_grants;
    SELECT * FROM audit_logs;
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

## Domain Vocabulary & Enums Reference

To maintain strict type safety and a clean architecture across modules, SpaceMedx uses centralized enumerations located in `app/enums/`:

### 1. User, Identity (`app.enums.user`)
- **`UserRole`**:
  - `sys_admin` — System Administrator
  - `org_admin` — Organization Administrator
  - `mission_admin` — Mission Administrator
  - `team_leader` — Team Leader
  - `astronaut` — Crew Member / Astronaut
  - `medical_officer` — Medical Officer
  - `researcher` — Science & Research Officer
  - `mission_control` — Ground Control Operator
  - `guest_viewer` — Read-only Observer
- **`AccountStatus`**:
  - `active` — Fully operational account
  - `invited` — Pending registration/activation
  - `suspended` — Temporarily disabled
  - `deactivated` — Permanently disabled
  - `offline` — Local habitat caching / disconnected space-flight operations mode

### 2. Environment & Location (`app.enums.environment`)
- **`MissionLocationType`**:
  - `space` — Deep space transit / orbital vessel
  - `moon` — Lunar surface base / outpost
  - `planet` — Planetary surface (e.g., Mars, Titan)
  - `habitat` — Orbital space station / ISS
  - `asteroid` — Asteroid mining facility
- **`EnvironmentalMetricType`**:
  - `atmospheric_pressure`, `co2_level`, `o2_level`, `radiation_exposure`, `ambient_temperature`, `humidity`, `cabin_airflow`
- **`EnvironmentAlertLevel`**:
  - `nominal`, `warning`, `critical`, `emergency`

### 3. Telemetry, Observations (`app.enums.observation`)
- **`ObservationQuality`**:
  - `Valid`, `Questionable`, `Invalid`, `Missing`
- **`ObservationSource`**:
  - `Simulator`, `Wearable`, `Manual`, `Medical Device`

### 4. Emergency Protocols (`app.enums.emergency`)
- **`EmergencyGrantStatus`**:
  - `active`, `expired`, `revoked`

### 5. Audit, Compliance (`app.enums.audit`)
- **`AuditAction`**:
  - `READ`, `CREATE`, `UPDATE`, `DELETE`, `SHARE`, `EXPORT`, `EMERGENCY_GRANT`, `EMERGENCY_REVOKE`