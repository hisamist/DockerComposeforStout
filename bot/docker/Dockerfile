# syntax=docker/dockerfile:1
# Image du bridge Discord <-> Stoat, construite à partir des sources de stoatcord-bot.
# Contexte principal : ./bot/stoatcord-bot (code amont, non modifié)
# Contexte additionnel "bridge" : ./bot/docker (nos fichiers : entrypoint.ts)

ARG BUN_VERSION=1.4.4

# ---------- Étape 1 : dépendances de production ----------
FROM oven/bun:${BUN_VERSION}-slim AS deps
WORKDIR /app
COPY package.json bun.lock ./
# Le bun.lock amont n'est pas synchronisé avec package.json, et --production le fige :
# on le resynchronise d'abord, puis on ne garde que les dépendances de production.
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install && rm -rf node_modules && bun install --production
# Répertoire de données préparé ici : l'image finale n'a pas de shell pour faire un mkdir
RUN mkdir -p /data

# ---------- Étape 2 : développement (toutes les dépendances, rechargement à chaud) ----------
FROM oven/bun:${BUN_VERSION}-slim AS dev
WORKDIR /app
COPY package.json bun.lock ./
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install
COPY tsconfig.json ./
COPY src/ ./src/
COPY --from=bridge entrypoint.ts ./
# Même utilisateur non-root qu'en production (le volume de données lui appartient)
RUN mkdir -p /data && chown 65532:65532 /data
USER 65532:65532
ENV NODE_ENV=development API_PORT=3210 DB_PATH=/data/stoatcord.db
EXPOSE 3210
CMD ["bun", "--watch", "entrypoint.ts"]

# ---------- Étape 3 : production (distroless : ni shell, ni gestionnaire de paquets) ----------
FROM oven/bun:${BUN_VERSION}-distroless AS runtime
LABEL org.opencontainers.image.title="stoatcord-bot (projetBridge)" \
      org.opencontainers.image.description="Bridge Discord <-> Stoat, image durcie multi-stage" \
      org.opencontainers.image.source="https://github.com/tribixbite/stoatcord-bot"
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json tsconfig.json ./
COPY src/ ./src/
COPY --from=bridge entrypoint.ts ./
# 65532 = utilisateur "nonroot" des images distroless
COPY --from=deps --chown=65532:65532 /data /data
ENV NODE_ENV=production API_PORT=3210 DB_PATH=/data/stoatcord.db
USER 65532:65532
EXPOSE 3210
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["bun", "-e", "const r = await fetch('http://127.0.0.1:3210/api/health'); process.exit(r.ok ? 0 : 1)"]
ENTRYPOINT ["bun"]
CMD ["entrypoint.ts"]
