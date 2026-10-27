# syntax=docker/dockerfile:1
# =============================================================================
#  Backend Stoat compilé depuis les sources (github.com/stoatchat/stoatchat)
#  Contexte : ./stoat/backend
#
#  Une seule étape de compilation Rust produit les 8 binaires du workspace.
#  Chaque service est une CIBLE (--target) finale distincte qui ne copie que
#  son binaire : docker compose construit "api", "events"... depuis ce fichier,
#  et BuildKit ne compile le workspace qu'une fois pour toutes les cibles.
# =============================================================================
ARG RUST_VERSION=1.92.0

# ---------- Compilation ----------
FROM rust:${RUST_VERSION}-slim-trixie AS builder
RUN apt-get update \
 && apt-get install -y --no-install-recommends make pkg-config libdav1d-dev libssl-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
# Mémoire limitée (Docker Desktop ~8 Go) : jobs réduits, LTO "thin" au lieu de "fat"
ARG CARGO_BUILD_JOBS=6
ARG CARGO_PROFILE_RELEASE_LTO=thin
ENV CARGO_PROFILE_RELEASE_LTO=${CARGO_PROFILE_RELEASE_LTO}
# Caches BuildKit : registre cargo et dossier target persistent entre deux builds,
# une modification du code ne recompile que les crates touchées.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target \
    cargo build --locked --release -j "${CARGO_BUILD_JOBS}" \
 && mkdir -p /out \
 && for bin in delta bonfire autumn january gifbox crond pushd voice-ingress; do \
      cp "target/release/revolt-$bin" /out/; \
    done

# ---------- Dépendances d'exécution ----------
# libdav1d (décodage AVIF) pour Autumn et January
FROM debian:13-slim AS runtime-libs
RUN apt-get update \
 && apt-get install -y --no-install-recommends libdav1d7 \
 && mkdir -p /runtime-libs \
 && for library in /usr/lib/*-linux-gnu/libdav1d.so.7*; do cp -a --parents "$library" /runtime-libs; done

# ffmpeg/ffprobe statiques (vignettes et métadonnées des vidéos)
FROM mwader/static-ffmpeg:7.1.1 AS ffmpeg

# busybox statique : sonde de santé (les images distroless n'ont ni shell ni curl)
FROM busybox:1.37-musl AS probe

# ---------- Socle commun : distroless, non-root ----------
FROM gcr.io/distroless/cc-debian13:nonroot AS base
WORKDIR /
COPY --from=probe /bin/busybox /usr/local/bin/busybox
COPY --from=runtime-libs /usr/bin/uname /usr/bin/uname
LABEL org.opencontainers.image.source="https://github.com/stoatchat/stoatchat" \
      org.opencontainers.image.description="Stoat compilé depuis les sources (projetBridge)"
USER nonroot

FROM base AS media-base
COPY --from=runtime-libs /runtime-libs/ /
COPY --from=ffmpeg /ffmpeg /ffprobe /usr/local/bin/

# ---------- Une cible par service ----------
FROM base AS api
COPY --from=builder /out/revolt-delta ./
ENV ROCKET_ADDRESS=0.0.0.0
EXPOSE 14702
CMD ["./revolt-delta"]

FROM base AS events
COPY --from=builder /out/revolt-bonfire ./
EXPOSE 14703
CMD ["./revolt-bonfire"]

FROM media-base AS file-server
COPY --from=builder /out/revolt-autumn ./
EXPOSE 14704
CMD ["./revolt-autumn"]

FROM media-base AS proxy
COPY --from=builder /out/revolt-january ./
EXPOSE 14705
CMD ["./revolt-january"]

FROM base AS gifbox
COPY --from=builder /out/revolt-gifbox ./
EXPOSE 14706
CMD ["./revolt-gifbox"]

FROM base AS crond
COPY --from=builder /out/revolt-crond ./
CMD ["./revolt-crond"]

FROM base AS pushd
COPY --from=builder /out/revolt-pushd ./
CMD ["./revolt-pushd"]

FROM base AS voice-ingress
COPY --from=builder /out/revolt-voice-ingress ./
CMD ["./revolt-voice-ingress"]
