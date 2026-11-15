"""Dataset discovery and local-file staging CLI."""
import argparse
import json
from pathlib import Path
from .catalog import list_datasets
from .ingest import asset_manifest, parse_bidmc_numerics, write_staging

def main():
    parser = argparse.ArgumentParser(description="SpaceMedx dataset source adapters")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    reg = sub.add_parser("register-asset")
    reg.add_argument("dataset_id")
    reg.add_argument("file", type=Path)
    reg.add_argument("--out", type=Path)
    bidmc = sub.add_parser("bidmc-numerics")
    bidmc.add_argument("file", type=Path)
    bidmc.add_argument("--out", type=Path, required=True)
    bidmc.add_argument("--limit", type=int)
    args = parser.parse_args()
    if args.action == "list":
        print(json.dumps(list_datasets(), indent=2))
    elif args.action == "register-asset":
        result = asset_manifest(args.dataset_id, args.file)
        if args.out: write_staging(result, args.out)
        else: print(json.dumps(result, indent=2))
    else:
        result = parse_bidmc_numerics(args.file, limit=args.limit)
        write_staging(result, args.out)
        print(json.dumps({"out":str(args.out), **result["counts"]}, indent=2))

if __name__ == "__main__": main()
