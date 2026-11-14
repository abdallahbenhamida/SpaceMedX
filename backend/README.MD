# SpaceMedx Backend

## Setup
- `cp env.example .env`

**SECRET_KEY:** `openssl rand -hex 32` / `python3 -c "import secrets; print(secrets.token_hex(32))"`

## Using Makefile (make)

**Registered commands:**
- `help`
- `up`
- `down`
- `build`
- `logs`
- `ps`
- `clean`
- `restart`
- `health`

## Tests
Using pytest for the backend side:
- `docker exec -it spacemedx-api pytest`

## Domain Vocabulary (Enums Reference)

To maintain strict type safety and a clean architecture across modules, SpaceMedx uses centralized enumerations located in `backend/app/enums/`.

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