# syntax=docker/dockerfile:1
# =============================================================================
#  Client web Stoat compilé depuis les sources (github.com/stoatchat/for-web)
#  Contexte : ./stoat/web
#
#  Les URLs de l'instance ne sont pas connues au build : Vite compile des
#  marqueurs (__VITE_API_URL__...) que inject.js remplace au démarrage par les
#  variables d'environnement. Une même image sert donc n'importe quel domaine.
# =============================================================================
ARG NODE_VERSION=24

# ---------- Dépendances (communes au développement et à la production) ----------
FROM node:${NODE_VERSION}-alpine AS deps
RUN apk add --no-cache git python3 make g++ \
 && corepack enable && corepack prepare pnpm@11.3.0 --activate
WORKDIR /build
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY packages/ packages/
COPY patches/ patches/
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile
# Dépendances internes du workspace : SDK stoat.js, composants LiveKit, traductions, CSS
RUN pnpm --filter stoat.js build \
 && pnpm --filter solid-livekit-components build \
 && pnpm --filter client exec lingui compile --typescript \
 && pnpm --filter client exec node scripts/copyAssets.mjs \
 && pnpm --filter client exec panda codegen \
 && pnpm --filter client exec lingui extract \
 && pnpm --filter client exec lingui compile --typescript

# ---------- Développement : serveur Vite avec rechargement à chaud (HMR) ----------
# Les VITE_* réelles sont fournies par docker-compose.override.yaml ; le code de
# packages/client/src est synchronisé par "docker compose watch".
FROM deps AS dev
ENV NODE_ENV=development BASE_PATH=/
EXPOSE 5000
CMD ["pnpm", "--filter", "client", "exec", "vite", "--host", "0.0.0.0", "--port", "5000", "--strictPort"]

# ---------- Compilation de production ----------
FROM deps AS builder
ENV VITE_HOST=__VITE_HOST__ \
    VITE_API_URL=__VITE_API_URL__ \
    VITE_DEV_WS_URL=__VITE_WS_URL__ \
    VITE_DEV_MEDIA_URL=__VITE_MEDIA_URL__ \
    VITE_DEV_PROXY_URL=__VITE_PROXY_URL__ \
    VITE_DEV_GIFBOX_URL=__VITE_GIFBOX_URL__ \
    VITE_RNNOISE_WORKLET_CDN_URL=__VITE_RNNOISE_WORKLET_CDN_URL__ \
    BASE_PATH=/
RUN NODE_OPTIONS="--max-old-space-size=4096" pnpm --filter client exec vite build

# ---------- Serveur statique ----------
FROM node:${NODE_VERSION}-alpine AS runtime
WORKDIR /app
COPY docker/package.json docker/inject.js ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force
COPY --from=builder /build/packages/client/dist ./dist
LABEL org.opencontainers.image.source="https://github.com/stoatchat/for-web" \
      org.opencontainers.image.description="Client web Stoat compilé depuis les sources (projetBridge)"
# Utilisateur non-root fourni par l'image node
USER node
EXPOSE 5000
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 \
    CMD wget -q -O /dev/null http://127.0.0.1:5000/ || exit 1
# Système de fichiers en lecture seule possible : l'injection écrit dans /tmp (tmpfs).
# inject.js lit ./dist et écrit ./dist_injected relativement au dossier courant.
CMD ["sh", "-c", "mkdir -p /tmp/web && cp -r /app/dist /tmp/web/dist && cd /tmp/web && node /app/inject.js && rm -rf dist && exec /app/node_modules/.bin/sirv dist_injected --port 5000 --cors --single --host"]
