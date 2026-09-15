#!/bin/sh
set -e

echo "Building acme.db..."
python prompt_inj_ch1/setup_db.py

echo "Starting server..."
exec uvicorn frontend.main:app --host 0.0.0.0 --port 8000
