#!/bin/sh
# Erzeugt die .env EINMALIG für den Pilot (GPU, qwen3-coder:30b, 64k Kontext, 3 parallele Anfragen).
# Ein zweiter Lauf würde neue Schlüssel erzeugen und die Datenbank unlesbar machen; deshalb bricht er ab.
set -eu
V=${CODENA_VERSION:-pilot-20261126}
ADDR=${1:?"Aufruf: ./setup-env.sh <Server-Adresse, z. B. 10.0.0.5 oder codena.firma.local>"}
if [ -e .env ]; then
  echo ".env existiert bereits; nichts geändert." >&2
  exit 1
fi
cp .env.example .env && chmod 600 .env
MK=$(docker run --rm --network none --entrypoint python "codena-backend-api:$V" -c \
  'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')
sed -i \
  -e "s|^CODENA_VERSION=.*|CODENA_VERSION=$V|" \
  -e "s|^COMPOSE_FILE=.*|COMPOSE_FILE=docker-compose.yml:docker-compose.gpu.yml|" \
  -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" \
  -e "s|^MASTER_ENCRYPTION_KEY=.*|MASTER_ENCRYPTION_KEY=$MK|" \
  -e "s|^SESSION_SECRET_KEY=.*|SESSION_SECRET_KEY=$(openssl rand -base64 32)|" \
  -e "s|^API_URL=.*|API_URL=http://$ADDR:8000|" \
  -e "s|^FRONTEND_URL=.*|FRONTEND_URL=http://$ADDR:3000|" \
  -e "s|^LEGACY_OLLAMA_SERVICE=.*|LEGACY_OLLAMA_SERVICE=true|" \
  -e "s|^OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL=http://ollama:11434|" \
  -e "s|^LLM_MODEL=.*|LLM_MODEL=qwen3-coder:30b|" \
  -e "s|^EMBEDDING_AUTO_PULL=.*|EMBEDDING_AUTO_PULL=false|" \
  -e "s|^OLLAMA_NUM_CTX=.*|OLLAMA_NUM_CTX=65536|" \
  -e "s|^OLLAMA_CONTEXT_LENGTH=.*|OLLAMA_CONTEXT_LENGTH=65536|" \
  -e "s|^OLLAMA_NUM_PARALLEL=.*|OLLAMA_NUM_PARALLEL=3|" \
  -e "s|^INFERENCE_MAX_CONCURRENCY=.*|INFERENCE_MAX_CONCURRENCY=3|" \
  .env
echo "COMPOSE_PROFILES=local-ollama" >> .env
echo ".env angelegt. Jetzt sichern (enthält MASTER_ENCRYPTION_KEY), dann: docker compose up -d --no-build"
