# =============================================================================
#  projetBridge : commandes courantes.   make help   pour la liste.
#
#  Portable Linux / macOS / Windows : sous Windows, GNU make exécute les
#  recettes avec cmd.exe. Elles n'utilisent donc que des commandes simples
#  (docker ...), sans syntaxe propre à bash.
# =============================================================================

.DEFAULT_GOAL := help

PROJECT     := projetbridge
STOAT_TAG   := v0.15.5
TRIVY_IMAGE := aquasec/trivy:0.64.1

# Les trois façons d'appeler Compose
PROD   := docker compose -f docker-compose.yaml
DEV    := docker compose
REMOTE := docker compose -f docker-compose.yaml -f docker-compose.remote.yaml --env-file .env --env-file .env.remote

# Service ciblé par logs / restart / shell :  make logs s=api
s ?= stoatcord-bot

# Indentation de make help ($(info) supprime les espaces en tête)
EMPTY :=
I := $(EMPTY)    $(EMPTY)

# Images construites par le projet (pour make scan)
IMAGES := stoat-api stoat-events stoat-file-server stoat-proxy stoat-gifbox \
          stoat-crond stoat-pushd stoat-voice-ingress

.PHONY: help setup build build-web prod dev up local remote monitoring tools \
        ps ps-remote logs logs-remote restart down down-remote config check scan

help:
	@$(info )
	@$(info  projetBridge : Stoat + bridge Discord)
	@$(info )
	@$(info  Installation)
	@$(info $(I)make setup        sources, configuration et secrets (Linux / macOS / Git Bash))
	@$(info $(I)make build        compile les images (backend Rust d'abord, puis le reste))
	@$(info )
	@$(info  Démarrage)
	@$(info $(I)make prod         stack de production)
	@$(info $(I)make dev          stack de développement + watch (premier plan, Ctrl+C pour quitter))
	@$(info $(I)make up           stack de développement en arrière-plan)
	@$(info $(I)make monitoring   + cAdvisor, Prometheus, Grafana (http://127.0.0.1:3000))
	@$(info $(I)make tools        + mongo-express (http://127.0.0.1:8081))
	@$(info )
	@$(info  Bridge : un seul à la fois (même token Discord))
	@$(info $(I)make local        bridge sur le backend de ce PC (arrête le bridge distant))
	@$(info $(I)make remote       bridge sur le backend distant via WireGuard (arrête le local))
	@$(info )
	@$(info  Suivi)
	@$(info $(I)make ps           état et santé des services (ps-remote : mode distant))
	@$(info $(I)make logs s=api   logs d'un service (logs-remote : mode distant))
	@$(info $(I)make restart s=X  redémarre un service)
	@$(info $(I)make check        valide les fichiers Compose et teste l'isolation réseau)
	@$(info $(I)make scan         analyse de vulnérabilités des images (Trivy))
	@$(info )
	@$(info  Arrêt (les données dans ./data et les volumes sont conservées))
	@$(info $(I)make down         arrête la stack locale)
	@$(info $(I)make down-remote  arrête le mode distant)
	@$(info )

# --- Installation ------------------------------------------------------------
setup:
	bash ./setup.sh

# Le backend Rust est compilé une fois (cible api) ; les 7 autres cibles et le
# client web réutilisent ensuite le cache BuildKit.
build:
	$(PROD) build api
	$(PROD) build

build-web:
	$(PROD) build web

# --- Démarrage ---------------------------------------------------------------
prod:
	$(PROD) up -d

dev:
	$(DEV) up --watch

up:
	$(DEV) up -d

monitoring:
	$(DEV) --profile monitoring up -d

tools:
	$(DEV) --profile tools up -d

# --- Bascule du bridge (toujours arrêter l'autre mode d'abord) ---------------
local:
	-$(REMOTE) stop stoatcord-bot
	$(DEV) up -d
	docker ps --filter name=stoatcord-bot --format "{{.Names}}  ({{.Status}})"

remote:
	$(DEV) stop stoatcord-bot
	$(REMOTE) up -d
	docker ps --filter name=stoatcord-bot --format "{{.Names}}  ({{.Status}})"

# --- Suivi -------------------------------------------------------------------
ps:
	$(DEV) ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"

ps-remote:
	$(REMOTE) ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"

logs:
	$(DEV) logs -f --tail 100 $(s)

logs-remote:
	$(REMOTE) logs -f --tail 100 $(s)

restart:
	$(DEV) restart $(s)

# --- Arrêt -------------------------------------------------------------------
down:
	$(DEV) --profile monitoring --profile tools down

down-remote:
	$(REMOTE) down

# --- Vérifications -----------------------------------------------------------
config:
	$(PROD) config --quiet
	$(DEV) config --quiet
	$(REMOTE) config --quiet
	@echo Configurations prod, dev et distant : valides

# Isolation réseau : un conteneur jetable placé sur le réseau "backend" (celui du
# bridge) doit joindre l'API mais aucune base de données.
NETCHECK := docker run --rm --network $(PROJECT)_backend busybox:1.37-musl sh -c
check: config
	@echo Isolation reseau depuis le reseau backend (celui du bridge) :
	@$(NETCHECK) "nc -z -w 2 api 14702 2>/dev/null && echo '  api:14702       JOIGNABLE (attendu)' || echo '  api:14702       BLOQUE (ANORMAL)'"
	@$(NETCHECK) "nc -z -w 2 database 27017 2>/dev/null && echo '  database:27017  JOIGNABLE (ANORMAL)' || echo '  database:27017  BLOQUE (attendu)'"
	@$(NETCHECK) "nc -z -w 2 redis 6379 2>/dev/null && echo '  redis:6379      JOIGNABLE (ANORMAL)' || echo '  redis:6379      BLOQUE (attendu)'"
	@$(NETCHECK) "nc -z -w 2 minio 9000 2>/dev/null && echo '  minio:9000      JOIGNABLE (ANORMAL)' || echo '  minio:9000      BLOQUE (attendu)'"
	@$(NETCHECK) "wget -q -T 3 -O /dev/null http://example.com 2>/dev/null && echo '  Internet        JOIGNABLE (ANORMAL)' || echo '  Internet        BLOQUE (attendu)'"

# Vulnérabilités HIGH et CRITICAL des images du projet (le cache Trivy est
# gardé dans un volume pour ne pas retélécharger la base à chaque fois).
TRIVY := docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v $(PROJECT)_trivy_cache:/root/.cache $(TRIVY_IMAGE) image --quiet --severity HIGH,CRITICAL --ignore-unfixed
scan: $(addprefix scan-,$(IMAGES)) scan-bot
scan-%:
	$(TRIVY) projetbridge/$*:$(STOAT_TAG)
scan-bot:
	$(TRIVY) projetbridge/stoatcord-bot:latest
