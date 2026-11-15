from typing import Any, Callable, Protocol
from pydantic import BaseModel, Field
from .contracts import ExecutionContext, InputManifest, ProcessingResult, AssessmentResult

class AlgorithmManifest(BaseModel):
    algorithm_id: str
    version: str
    kind: str
    output_type: str
    supported_modes: list[str] = Field(default_factory=lambda: ["BATCH", "REPLAY"])
    validation_status: str = "SOFTWARE_VERIFIED"
    approved_for_operational_alerts: bool = False

class Algorithm(Protocol):
    manifest: AlgorithmManifest
    def execute(self, data: InputManifest, context: ExecutionContext) -> ProcessingResult | AssessmentResult: ...

class Registry:
    def __init__(self):
        self._factories: dict[tuple[str, str], Callable[[], Algorithm]] = {}

    def register(self, manifest: AlgorithmManifest, factory: Callable[[], Algorithm]):
        key = (manifest.algorithm_id, manifest.version)
        if key in self._factories:
            raise ValueError(f"Duplicate algorithm registration: {key}")
        self._factories[key] = factory

    def create(self, algorithm_id: str, version: str) -> Algorithm:
        key = (algorithm_id, version)
        if key not in self._factories:
            raise KeyError(f"Unregistered algorithm {key}")
        algorithm = self._factories[key]()
        if (algorithm.manifest.algorithm_id, algorithm.manifest.version) != key:
            raise ValueError("Algorithm manifest does not match registration")
        return algorithm

    def list(self) -> list[dict[str, Any]]:
        return [self.create(*key).manifest.model_dump() for key in sorted(self._factories)]
