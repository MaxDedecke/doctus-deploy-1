#!/bin/sh
# Zieht die drei Codena-Images aus der GitHub Container Registry und gibt ihnen die lokalen Namen, die
# docker-compose.yml erwartet. Vorher: docker login ghcr.io -u maxdedecke (Passwort: Lese-Token).
set -eu
OWNER=${OWNER:-maxdedecke}
V=${CODENA_VERSION:-pilot-20261126}
for i in backend-api parser-worker frontend; do
  docker pull "ghcr.io/$OWNER/codena-$i:$V"
  docker tag "ghcr.io/$OWNER/codena-$i:$V" "codena-$i:$V"
done
docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' | grep "^codena-.*:$V"
echo "Fertig. Danach: docker logout ghcr.io"
