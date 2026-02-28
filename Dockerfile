# syntax=docker/dockerfile:1

ARG SITE=portal

# =========================
# Stage 1: Frontend builder
# =========================
FROM node:20.20-bookworm-slim AS frontend-builder
ARG SITE
WORKDIR /builder

ENV YARN_CACHE_FOLDER=/tmp/yarn-cache

# Copy both frontend + backend (build writes into backend static path)
COPY ./sites/${SITE}/src /builder/sites/${SITE}/src
WORKDIR /builder/sites/${SITE}/src/frontend

RUN yarn install --frozen-lockfile && \
    yarn compile-translations && \
    yarn build-ts-production && \
    yarn build-sass-production && \
    rm -rf /tmp/yarn-cache

# =========================
# Stage 2: Python deps builder
# =========================
FROM python:3.11-slim-bookworm AS python-builder
ARG SITE
WORKDIR /builder

# Only PostgreSQL build deps (no MySQL)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY ./sites/${SITE}/requirements/base.txt /builder/requirements.txt

RUN python -m pip install --upgrade pip && \
    python -m pip install --no-cache-dir --prefix=/install -r /builder/requirements.txt

# =========================
# Stage 3: Runtime image
# =========================
FROM python:3.11-slim-bookworm AS production
ARG SITE
ENV SITE=${SITE}
ENV PYTHONUNBUFFERED=1

# Runtime deps only (no build-essential here)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gettext \
        libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python deps
COPY --from=python-builder /install /usr/local

WORKDIR /app

# Backend code
COPY ./sites/${SITE}/src/backend /app/

# Compiled frontend assets
COPY --from=frontend-builder \
    /builder/sites/${SITE}/src/backend/base/static/richie \
    /app/base/static/richie

# Build-time Django steps (inline secret for linter safety)
RUN mkdir -p locale && \
    DJANGO_SECRET_KEY=dummy-build-secret python manage.py compilemessages && \
    DJANGO_SECRET_KEY=dummy-build-secret python manage.py collectstatic --noinput

EXPOSE 8000

CMD ["sh", "-lc", "gunicorn -b 0.0.0.0:8000 ${SITE}.wsgi:application"]
