"""Integration router. Replace demo API-key gate with host RBAC before deployment."""
import os
from uuid import UUID
from fastapi import FastAPI, HTTPException, Header, Depends
from pydantic import BaseModel, Field
from .processing.database import Store
from .processing.registry import Registry
from .processing.demo import RecordCountDemo
from .processing.contracts import InputManifest
from .datasets.catalog import list_datasets, get_dataset
from .processing.service import ProcessingService, JobConflict

registry = Registry()
registry.register(RecordCountDemo.manifest, RecordCountDemo)

class SubmitRequest(BaseModel):
    algorithm_id: str
    version: str
    manifest: InputManifest
    configuration: dict = Field(default_factory=dict)
    scope_id: str = Field(min_length=1)
    idempotency_key: str = Field(min_length=1)


def create_app(store: Store | None = None, require_auth: bool = True) -> FastAPI:
    app = FastAPI(title="SpaceMedx Processing Foundation", version="3.2.0")
    db = store or Store()
    service = ProcessingService(db, registry)

    def guard(x_api_key: str | None = Header(default=None)):
        expected = os.environ.get("SPACEMEDX_DEMO_API_KEY")
        if require_auth and (not expected or x_api_key != expected):
            raise HTTPException(401, "Host authentication not configured or invalid demo key")
        return "demo-user"

    @app.get("/health")
    def health(): return {"status":"ok", "version":"3.2.0"}

    @app.get("/api/v1/datasets", dependencies=[Depends(guard)])
    def datasets(): return list_datasets()

    @app.get("/api/v1/datasets/{dataset_id}", dependencies=[Depends(guard)])
    def dataset(dataset_id: str):
        try: return get_dataset(dataset_id).__dict__
        except KeyError: raise HTTPException(404, "Unknown dataset")

    @app.get("/api/v1/processing/algorithms", dependencies=[Depends(guard)])
    def algorithms(): return registry.list()

    @app.post("/api/v1/processing/jobs", status_code=202)
    def submit(request: SubmitRequest, actor: str = Depends(guard)):
        try:
            jid = service.submit(algorithm_id=request.algorithm_id, version=request.version,
                manifest=request.manifest, configuration=request.configuration, scope_id=request.scope_id,
                idempotency_key=request.idempotency_key, actor=actor)
        except JobConflict as exc:
            raise HTTPException(409, str(exc)) from exc
        except KeyError as exc:
            raise HTTPException(422, str(exc)) from exc
        return {"job_id":jid, "status_url":f"/api/v1/processing/jobs/{jid}"}

    @app.get("/api/v1/processing/jobs/{job_id}")
    def get_job(job_id: UUID, actor: str = Depends(guard)):
        value = service.get(str(job_id))
        if not value: raise HTTPException(404, "Job not found")
        return value

    return app

# ASGI app is constructed lazily to avoid database-driver import during contract-only tests.
class LazyApp:
    def __init__(self):
        self._app = None
    async def __call__(self, scope, receive, send):
        if self._app is None:
            self._app = create_app()
        await self._app(scope, receive, send)

app = LazyApp()
