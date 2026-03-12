#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "==========================================="
echo "  e-SUS Dashboard - Inicialização Automática"
echo "==========================================="

if ! command -v node >/dev/null 2>&1; then
  echo "[ERRO] Node.js não encontrado. Instale Node.js 18+ e rode novamente."
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[ERRO] npm não encontrado. Instale npm e rode novamente."
  exit 1
fi

if [ ! -f .env ]; then
  cp .env.example .env
  echo "[OK] Arquivo .env criado automaticamente."
fi

set -a
source .env
set +a

: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
: "${PGDATABASE:=esus}"
: "${PGUSER:=esus}"
: "${PGPASSWORD:=esus}"

export PGPASSWORD

echo "[1/3] Instalando dependências do dashboard..."
if [ ! -d node_modules ]; then
  npm install
else
  echo "[OK] Dependências já instaladas."
fi

echo "[2/3] Configurando auditoria no banco..."
if command -v psql >/dev/null 2>&1; then
  psql -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -f sql/01_setup_auditoria.sql >/tmp/esus_audit_setup.log 2>&1 || {
    echo "[ERRO] Falha ao configurar auditoria com psql."
    echo "Detalhes em: /tmp/esus_audit_setup.log"
    exit 1
  }
  echo "[OK] Auditoria configurada com psql."
else
  echo "[AVISO] psql não encontrado. Usando setup via Node.js..."
  node setup_auditoria.js || exit 1
fi

echo "[3/3] Iniciando dashboard..."
echo "Abra no navegador: http://localhost:${PORT:-3000}"
exec npm start
