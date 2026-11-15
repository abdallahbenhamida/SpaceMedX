"""Non-clinical framework smoke-test algorithm; no physiological interpretation."""
from .contracts import ExecutionContext, InputManifest, ProcessingResult, ExecutionStatus, QualityProfile
from .registry import AlgorithmManifest

class RecordCountDemo:
    manifest = AlgorithmManifest(algorithm_id="SMX-DEMO-001", version="1.0.0", kind="PROCESSOR", output_type="record_count")

    def execute(self, data: InputManifest, context: ExecutionContext) -> ProcessingResult:
        return ProcessingResult(processing_run_id=context.run_id, algorithm_id=self.manifest.algorithm_id,
            algorithm_version=self.manifest.version, execution_status=ExecutionStatus.COMPLETED,
            output_type="record_count", output_refs=[f"count:{len(data.references)}"],
            quality_profile=QualityProfile(status="UNKNOWN"), provenance=data.references,
            warnings=["Demonstration only; does not assess health"])
