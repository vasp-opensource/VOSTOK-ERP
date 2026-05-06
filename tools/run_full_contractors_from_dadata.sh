#!/usr/bin/env bash
set -euo pipefail

# macOS/Linux launcher for full contractors fill from DaData.
# Mirrors settings from run_full_contractors_from_dadata.bat.

export VOSTOK_DB_HOST="172.16.1.248"
export VOSTOK_DB_PORT="3306"
export VOSTOK_DB_NAME="VOSTOK_ERP"
export VOSTOK_DB_USER="dadata"
export VOSTOK_DB_PASSWORD="MZZXF@OByLfH4t]!"
export DADATA_TOKEN="ad334e002cb51abbdd55c5875bceaed515e6907a"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "${SCRIPT_DIR}/fill_contractors_from_dadata.py" --limit 100
