#!/bin/sh
# Zieht die drei Doctus-Images aus der GitHub Container Registry und gibt ihnen die lokalen Namen, die
# docker-compose.yml erwartet. Vorher: docker login ghcr.io -u maxdedecke (Passwort: Lese-Token).
set -eu
OWNER=${OWNER:-maxdedecke}
V=${DOCTUS_VERSION:-pilot-20261122}
for i in backend-api parser-worker frontend deployer; do
  docker pull "ghcr.io/$OWNER/doctus-$i:$V"
  docker tag "ghcr.io/$OWNER/doctus-$i:$V" "doctus-$i:$V"
done
docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' | grep "^doctus-.*:$V"
echo "Fertig. Danach: docker logout ghcr.io"
