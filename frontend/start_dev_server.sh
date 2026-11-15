#!/usr/bin/env sh
# Crew Health Monitor (standalone frontend, demo data): serves this folder on http://localhost:8080/
cd "$(dirname "$0")"
python3 -m http.server 8080
