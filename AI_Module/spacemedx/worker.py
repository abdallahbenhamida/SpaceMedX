"""Single-worker CLI. Production deployments require operational supervision."""
import argparse
import logging
import time
from uuid import uuid4
from .processing.database import Store
from .processing.service import ProcessingService
from .app import registry

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--once", action="store_true")
    p.add_argument("--poll-seconds", type=float, default=2)
    args = p.parse_args()
    store = Store()
    service = ProcessingService(store, registry)
    worker_id = "worker-" + str(uuid4())
    while True:
        job = service.claim(worker_id)
        if job:
            try:
                service.execute_claimed(job, worker_id)
                log.info("completed job %s", job)
            except Exception:
                log.exception("failed job %s", job)
        elif args.once:
            break
        else:
            time.sleep(max(0.1, args.poll_seconds))
        if args.once:
            break

if __name__ == "__main__": main()
