#!/usr/bin/env bash
# "Cómo se hace un release": avanza los submódulos a main y commitea el bump.
# Uso: scripts/bump-submodules.sh [-y|--yes]   (-y = no interactivo)
set -euo pipefail
cd "$(dirname "$0")/.."
yes=0; [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && yes=1
git submodule update --init
git submodule update --remote apps/backend apps/frontend
git submodule summary
if git diff --quiet -- apps/backend apps/frontend; then echo "Nada que actualizar."; exit 0; fi
if [[ $yes -eq 0 ]]; then
  read -r -p "¿Commitear este bump? [y/N] " a
  [[ "$a" =~ ^[yY]$ ]] || { echo "Cancelado (submódulos quedan modificados; git submodule update para revertir)."; exit 1; }
fi
api=$(git -C apps/backend rev-parse --short=7 HEAD)
web=$(git -C apps/frontend rev-parse --short=7 HEAD)
git add apps/backend apps/frontend
git commit -m "chore(release): bump apps (api $api, web $web)"
echo "Listo. Haz push a main para disparar release.yml."
