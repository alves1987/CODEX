#!/usr/bin/env bash
set -euo pipefail

echo "==========================================="
echo " Iniciando dashboard do e-SUS"
echo "==========================================="
echo "Aguarde... no final abra: http://localhost:3000"
echo

cd "$(dirname "$0")/realtime-dashboard"
exec ./auto_run.sh
