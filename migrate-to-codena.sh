#!/bin/sh
# Einmaliger Umstieg einer bestehenden Doctus-Installation auf Codena, ohne Daten oder Einstellungen zu verlieren.
#
# Im Installationsordner ausführen (dort, wo .env und data/ liegen), nachdem ./pull-images.sh die Codena-Images
# geladen hat. Datenbank, Modelle, Repositories und .env-Schlüssel bleiben unverändert; geändert werden nur
# Namen: Compose-Projekt doctus -> codena, DOCTUS_* -> CODENA_* in der .env.
#
# Bleibt bewusst erhalten: der Datenbankname (POSTGRES_DB), MASTER_ENCRYPTION_KEY, alle Profile, Quellen,
# Nutzer, Teams, Projekte, Links und Erkenntnisse sowie bereits ausgegebene MCP- und CI-Tokens.
# Einmal neu anmelden müssen sich alle Nutzer (die Sitzungen werden neu signiert).
set -eu

NEW=${CODENA_VERSION:-pilot-20261126}
say() { printf '==> %s\n' "$*"; }
fail() { printf 'Abbruch: %s\n' "$*" >&2; exit 1; }

[ -f .env ] || fail "keine .env im aktuellen Ordner – im Installationsordner ausführen"
[ -d data/postgres ] || fail "data/postgres fehlt – im Installationsordner ausführen"
for image in backend-api parser-worker frontend; do
  docker image inspect "codena-$image:$NEW" >/dev/null 2>&1 \
    || fail "Image codena-$image:$NEW fehlt – zuerst ./pull-images.sh ausführen"
done
grep -q '^MASTER_ENCRYPTION_KEY=.' .env || fail "MASTER_ENCRYPTION_KEY fehlt in .env – Original-.env wiederherstellen"

stamp=$(date +%Y%m%d-%H%M%S)
backup=".env.vor-codena-$stamp"
cp -p .env "$backup"
say ".env gesichert als $backup"

# DOCTUS_VERSION wird CODENA_VERSION mit dem neuen Stand; alle übrigen DOCTUS_* behalten ihren Wert unter neuem Namen.
sed -i \
  -e "s|^DOCTUS_VERSION=.*|CODENA_VERSION=$NEW|" \
  -e "s|^CODENA_VERSION=.*|CODENA_VERSION=$NEW|" \
  -e 's|^DOCTUS_\([A-Z0-9_]*\)=|CODENA_\1=|' \
  -e 's|^COMPOSE_PROJECT_NAME=doctus$|COMPOSE_PROJECT_NAME=codena|' \
  .env
grep -q '^CODENA_VERSION=' .env || printf 'CODENA_VERSION=%s\n' "$NEW" >> .env

# Der Standardpfad des beobachteten Ordners hieß früher /tmp/doctus-watched; eine Ordnerquelle soll nach dem
# Umstieg denselben Ordner sehen, nicht still einen leeren.
if [ -d /tmp/doctus-watched ] && ! grep -q '^WATCHED_FOLDER=.' .env; then
  if grep -q '^WATCHED_FOLDER=' .env; then
    sed -i 's|^WATCHED_FOLDER=.*|WATCHED_FOLDER=/tmp/doctus-watched|' .env
  else
    echo 'WATCHED_FOLDER=/tmp/doctus-watched' >> .env
  fi
  say "WATCHED_FOLDER auf den bisherigen Standardordner /tmp/doctus-watched gesetzt"
fi
say ".env umgestellt: CODENA_VERSION=$NEW"

# Eigene Zusatzdateien (z. B. docker-compose.proxy.yml) gehören nicht zum Begleitrepo; Fundstellen nur melden.
compose_files=$(sed -n 's/^COMPOSE_FILE=//p' .env | tr ':' ' ')
for file in $compose_files; do
  case "$file" in docker-compose.yml|docker-compose.gpu.yml) continue ;; esac
  if [ -f "$file" ] && grep -n 'doctus' "$file" >/dev/null; then
    printf 'Hinweis: %s nennt noch "doctus" – bitte prüfen (Dienstnamen wie ollama oder backend-api sind unverändert):\n' "$file"
    grep -n 'doctus' "$file" | sed 's/^/    /'
  fi
done

# Vom Deployer geladene Modelle liegen im Volume doctus_llm_models; ohne Deployer ist es leer oder fehlt.
if docker volume inspect doctus_llm_models >/dev/null 2>&1 && ! docker volume inspect codena_llm_models >/dev/null 2>&1; then
  say "Modellvolume doctus_llm_models -> codena_llm_models kopieren"
  docker volume create codena_llm_models >/dev/null
  docker run --rm --network none --entrypoint sh \
    -v doctus_llm_models:/from:ro -v codena_llm_models:/to \
    "codena-backend-api:$NEW" -c 'cp -a /from/. /to/'
fi

# Erst jetzt die alten Container stoppen: alle Vorbereitungen sind erledigt, die Ausfallzeit bleibt kurz.
old=$(docker ps -aq --filter label=com.docker.compose.project=doctus)
if [ -n "$old" ]; then
  say "Container des Compose-Projekts doctus entfernen (Daten unter data/ und repos/ bleiben)"
  # shellcheck disable=SC2086
  docker rm -f $old >/dev/null
fi
docker network rm doctus_default >/dev/null 2>&1 || true

say "Codena starten"
docker compose up -d --no-build

# --noproxy: Ein HTTP(S)_PROXY in der Shell würde sonst auch localhost über den Firmenproxy schicken.
# Gewartet wird auf /health/live (läuft der Prozess?); /health prüft zusätzlich den LLM-Endpunkt und
# meldet 503, wenn ein Firmen-LLM dessen Modellliste nicht ausliefert – das ist kein Grund zum Abbruch.
printf 'Warte auf das Backend (üblich: unter einer Minute)'
i=0
until curl -fsS --noproxy '*' http://localhost:8000/health/live >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || { echo; fail "Backend nach 5 Minuten nicht erreichbar – docker compose logs backend-api prüfen"; }
  printf '.'
  sleep 5
done
echo
curl -sS --noproxy '*' http://localhost:8000/version || true
echo
echo "Zustand der Abhängigkeiten (ein Fehler nur beim LLM-Eintrag ist unkritisch, wenn der Chat funktioniert):"
curl -sS --noproxy '*' http://localhost:8000/health || true
echo
docker compose ps
cat <<EOF

Umstieg abgeschlossen. Alle Einstellungen, Daten und Tokens sind übernommen.
- Jede Person meldet sich einmal neu an; Darstellungsoptionen im Browser (Theme, Sprache) einmal neu wählen.
- Zurück auf den alten Stand: docker compose down, cp $backup .env, alten Stand des Begleitrepos auschecken,
  docker compose up -d --no-build (die alten doctus-Images bleiben bis zum Aufräumen lokal liegen).
- Später aufräumen: docker image rm \$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^doctus-')
EOF
