#!/usr/bin/env bash
# Installation de projetBridge (Linux, macOS ou Git Bash sous Windows) :
#   ./setup.sh [url-publique]     (par défaut : http://stoat.localhost)
#   ex. ./setup.sh https://chat.mondomaine.fr
# Idempotent : ne refait que les étapes manquantes, ne remplace jamais un secret existant.
set -euo pipefail
cd "$(dirname "$0")"

# En local : un sous-domaine de .localhost en HTTP. Les navigateurs le résolvent vers
# 127.0.0.1 et le traitent comme une origine sûre ; dans Docker, il désigne Caddy.
PUBLIC_URL="${1:-http://stoat.localhost}"
PUBLIC_URL="${PUBLIC_URL%/}"
DOMAIN="${PUBLIC_URL#*://}"
case "$PUBLIC_URL" in
  https://*) PUBLIC_WS="wss://$DOMAIN" ;;
  http://*)  PUBLIC_WS="ws://$DOMAIN" ;;
  *) echo "L'URL doit commencer par http:// ou https://" >&2; exit 1 ;;
esac

# --- Sources amont, à des versions figées ----------------------------------
clone_pinned() { # <dépôt> <tag ou commit> <dossier> [options git clone]
  if [ ! -d "$3/.git" ]; then
    echo "==> Clonage de $1 ($2)"
    git clone --quiet --depth 1 --branch "$2" "${@:4}" "$1" "$3" 2>/dev/null \
      || { git clone --quiet "${@:4}" "$1" "$3" && git -C "$3" checkout --quiet "$2"; }
  fi
}
clone_pinned https://github.com/stoatchat/stoatchat     v0.15.5               stoat/backend
clone_pinned https://github.com/stoatchat/for-web       stoat-for-web-v0.15.3 stoat/web \
  --recurse-submodules --shallow-submodules
clone_pinned https://github.com/tribixbite/stoatcord-bot 9ccb0eae3bf37fa95a145dac0a7df5cb7f81cf90 bot/stoatcord-bot

# --- Variables et secrets de la stack (.env) --------------------------------
rand() { openssl rand -hex 24; }
set_var() { # <clé> <valeur> : ajoute la variable si elle est absente
  touch .env
  grep -q "^$1=" .env || printf '%s=%s\n' "$1" "$2" >> .env
}

if [ ! -f .env ]; then
  echo "==> Création de .env (mots de passe aléatoires)"
  while IFS= read -r line; do
    if [[ "$line" == *=change_me ]]; then echo "${line%=change_me}=$(rand)"; else echo "$line"; fi
  done < .env.example > .env
fi
sed -i.bak -e "s#^STOAT_PUBLIC_URL=.*#STOAT_PUBLIC_URL=$PUBLIC_URL#" \
           -e "s#^STOAT_PUBLIC_WS=.*#STOAT_PUBLIC_WS=$PUBLIC_WS#" \
           -e "s#^STOAT_DOMAIN=.*#STOAT_DOMAIN=$DOMAIN#" .env && rm -f .env.bak

# Secrets internes de Stoat (remplacent generate_config.sh de stoatchat/self-hosted)
if ! grep -q "^STOAT_VAPID_PRIVATE_KEY=" .env; then
  echo "==> Génération des clés VAPID (notifications Web Push)"
  tmp="$(mktemp)"
  openssl ecparam -name prime256v1 -genkey -noout -out "$tmp"
  set_var STOAT_VAPID_PRIVATE_KEY "$(base64 < "$tmp" | tr -d '\n=')"
  set_var STOAT_VAPID_PUBLIC_KEY "$(openssl ec -in "$tmp" -outform DER 2>/dev/null | tail -c 65 | base64 | tr '/+' '_-' | tr -d '\n=')"
  rm -f "$tmp"
fi
set_var STOAT_FILES_ENCRYPTION_KEY "$(openssl rand -base64 32)"
set_var LIVEKIT_SECRET "$(rand)"

# --- Secrets Docker du bridge (un fichier par secret) -----------------------
mkdir -p secrets data
touch secrets/discord_token.txt secrets/stoat_token.txt
[ -s secrets/bridge_api_key.txt ] || rand | tr -d '\n' > secrets/bridge_api_key.txt
chmod 600 secrets/* .env 2>/dev/null || true

cat <<EOF

Installation prête pour $PUBLIC_URL. Étapes suivantes :
  1. Coller le token du bot Discord dans secrets/discord_token.txt
  2. Compiler puis démarrer Stoat (1re compilation Rust : 20 à 40 min) :
       docker compose -f docker-compose.yaml build api
       docker compose -f docker-compose.yaml up -d --build --scale stoatcord-bot=0
  3. Ouvrir $PUBLIC_URL, créer un compte puis un bot (Paramètres > Mes bots)
     et coller son token dans secrets/stoat_token.txt
  4. docker compose -f docker-compose.yaml up -d      (production)
     ou docker compose up --watch                    (développement)
EOF
