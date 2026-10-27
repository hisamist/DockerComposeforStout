#!/usr/bin/env bash
# Bascule le bridge entre le backend LOCAL et le backend DISTANT (WireGuard).
#   ./switch.sh local     -> bridge sur la stack Stoat de ce PC
#   ./switch.sh remote    -> bridge sur le backend de l'autre PC (.env.remote)
# Les deux modes partagent le même token Discord : un seul bridge doit tourner
# à la fois. Le script arrête toujours l'autre mode avant de démarrer celui demandé.
set -euo pipefail
cd "$(dirname "$0")"

local_c=(docker compose)
remote_c=(docker compose -f docker-compose.yaml -f docker-compose.remote.yaml
          --env-file .env --env-file .env.remote)

case "${1:-}" in
  local)
    echo "==> Arrêt du bridge distant";   "${remote_c[@]}" stop stoatcord-bot
    echo "==> Démarrage de la stack locale"; "${local_c[@]}" up -d
    url="http://stoat.localhost" ;;
  remote)
    [ -f .env.remote ] || { echo ".env.remote manquant : copier .env.remote.example" >&2; exit 1; }
    echo "==> Arrêt du bridge local";    "${local_c[@]}" stop stoatcord-bot
    echo "==> Démarrage du mode distant"; "${remote_c[@]}" up -d
    url="http://localhost:8080" ;;
  *) echo "Usage : ./switch.sh local|remote" >&2; exit 1 ;;
esac

echo; echo "==> Bridges en cours d'exécution :"
docker ps --filter "name=stoatcord-bot" --format "  {{.Names}}  ({{.Status}})"
echo; echo "Client web : $url"
