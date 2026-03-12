#!/usr/bin/env bash
set -euo pipefail

# Resolve os conflitos conhecidos deste PR mantendo a versão da branch atual (OURS)
FILES=(
  "MONITORAMENTO_TABELAS_ESUS.md"
  "realtime-dashboard/README.md"
  "realtime-dashboard/auto_run.sh"
  "realtime-dashboard/sql/01_setup_auditoria.sql"
)

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[ERRO] Execute dentro de um repositório Git."
  exit 1
fi

if ! git diff --name-only --diff-filter=U | grep -q .; then
  echo "[INFO] Não há conflitos em aberto."
  exit 0
fi

echo "[1/2] Aplicando versão da branch atual para arquivos em conflito..."
for f in "${FILES[@]}"; do
  if git ls-files --unmerged -- "$f" | grep -q .; then
    git checkout --ours -- "$f"
    git add "$f"
    echo "[OK] Resolvido: $f"
  fi
done

echo "[2/2] Status final:"
git status --short

echo
echo "Se tudo estiver certo, finalize com:"
echo "git commit -m 'resolve: conflitos do PR'"
