# Codena Pilot – Begleitdateien (pilot-20261126)

Alles, was die Deployment-Maschine neben den drei Images braucht. Images und Stand: Commit `f8a9401`,
Datenmodell 2.1.0, Migrationen bis `0052` (laufen beim ersten Start automatisch).

Das Produkt hieß bis 25.11.2026 Doctus. **Bestehende Installation? Dann nur den Abschnitt „Umstieg von Doctus“ ausführen**,
nicht den Ablauf für eine Neuinstallation.

| Datei | Zweck |
|---|---|
| `docker-compose.yml`, `docker-compose.gpu.yml` | Dienste; die GPU-Datei gibt Ollama die Grafikkarten |
| `.env.example` | Vorlage der Einstellungen (nie eine ausgefüllte `.env` einchecken) |
| `config/features.json` | Funktionsschalter |
| `pull-images.sh` | Images aus `ghcr.io` ziehen und lokal benennen |
| `migrate-to-codena.sh` | Einmaliger Umstieg einer bestehenden Doctus-Installation, ohne Daten oder Einstellungen zu verlieren |
| `setup-env.sh` | `.env` einmalig für den Pilot erzeugen (GPU, `qwen3-coder:30b`, 64k, 3 parallel) |
| `generate_diagnostics.py` | Diagnosepaket bei Problemen |
| `test-remote-inference.sh`, `check_remote_inference.py` | Nur für einen getrennten Modellserver |

## Umstieg von Doctus (bestehende Installation, einmalig)

Datenbank, Modelle, Repositories, `.env`-Schlüssel und alle Einstellungen bleiben erhalten: KI- und Embedding-Profile,
Wissensquellen samt Zugangsdaten, Nutzer, Teams, Projekte, Links und Erkenntnisse. Bereits ausgegebene MCP- und
CI-Tokens gelten weiter. Ausfallzeit: wenige Minuten.

```sh
cd ~/doctus                                          # bisheriger Installationsordner, dort liegen .env und data/
cp .env /sicherer/ort/doctus.env.vor-codena          # zusätzliche Sicherung außerhalb des Ordners
git pull                                             # neuer Stand dieses Repositorys

docker login ghcr.io -u maxdedecke                  # Passwort: Lese-Token
./pull-images.sh
docker logout ghcr.io

./migrate-to-codena.sh
```

Das Skript sichert die `.env` (`.env.vor-codena-<Zeit>`), benennt `DOCTUS_*` in `CODENA_*` um, entfernt die
Container des alten Compose-Projekts `doctus` und startet Codena mit denselben Daten. Der Datenbankname bleibt
`doctus`; das ist so gewollt. Eigene Zusatzdateien wie `docker-compose.proxy.yml` bleiben unverändert; nennt eine
davon noch `doctus`, zeigt das Skript die Stelle an (Dienstnamen wie `ollama` oder `backend-api` sind gleich
geblieben, nur Container heißen jetzt `codena-*`).

Danach meldet sich jede Person einmal neu an. Wer die VS-Code-Erweiterung nutzt, installiert die neue
Codena-Erweiterung und trägt das persönliche Token einmal neu ein. Der Ordner `~/doctus` darf so heißen bleiben.

Zurück auf den alten Stand: `docker compose down`, die gesicherte `.env` zurückkopieren,
`git checkout fcca506` (letzter Doctus-Stand dieses Repositorys), `docker compose up -d --no-build`.

## Voraussetzungen (Neuinstallation)

- Ubuntu 24.04 (oder vergleichbar), Docker mit Compose v2, `git`, `openssl`.
- NVIDIA-Treiber und NVIDIA Container Toolkit: `docker info | grep -i nvidia` muss die Runtime zeigen.
- Internet zu `ghcr.io`, Docker Hub (PostgreSQL, Valkey, Ollama per Digest) und `ollama.com` (Modelle, ~20 GB).
- Lese-Token (classic, `read:packages`; `repo`, falls dieses Repository damit geklont wird).
- Betrieb als normaler Nutzer (z. B. `codenaops`) ohne sudo: Ein Administrator nimmt ihn einmalig in die Gruppe
  `docker` auf (`usermod -aG docker codenaops`, danach neu anmelden); `docker ps` muss dann ohne sudo gehen.
  Die Gruppe `docker` ist gleichwertig zu root auf dem Host. Git, Docker und NVIDIA-Toolkit muss der
  Administrator vorab installieren.

## Ablauf (Neuinstallation)

```sh
git clone https://github.com/maxdedecke/doctus-deploy-1.git ~/codena && cd ~/codena

docker login ghcr.io -u maxdedecke                  # Passwort: Lese-Token
./pull-images.sh
docker logout ghcr.io

./setup-env.sh <server-adresse>                      # genau einmal; legt .env an
cp .env /sicherer/ort/codena.env                     # sofort sichern: ohne MASTER_ENCRYPTION_KEY ist alles unlesbar

docker compose up -d --no-build
docker exec codena-ollama ollama pull hf.co/gpustack/bge-m3-GGUF:Q4_K_M
docker exec codena-ollama ollama cp hf.co/gpustack/bge-m3-GGUF:Q4_K_M bge-m3
docker exec codena-ollama ollama pull hf.co/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M   # ~19 GB
docker exec codena-ollama ollama cp hf.co/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M qwen3-coder:30b
docker compose logs backend-api | grep -A3 "Erster Start" # Admin-Passwort, wird nur einmal angezeigt
docker compose ps
curl -fsS http://localhost:8000/health && curl -fsS http://localhost:8000/version
```

`--no-build` ist Pflicht: Die Compose-Datei enthält Build-Abschnitte für Verzeichnisse, die es hier nicht gibt.

Die Container laufen intern als root; was sie unter `data/` und `repos/` anlegen, gehört daher root. Ohne sudo
löscht man es über einen Container, z. B. `docker run --rm -v "$PWD/data:/d" alpine rm -rf /d/logs`.

## Prüfen

- `docker exec codena-ollama ollama ps` nach der ersten Chatfrage: `PROCESSOR` muss „100% GPU“ zeigen, `CONTEXT`
  65536. Steht dort ein CPU-Anteil, ist das Modell nicht ganz in den Grafikspeicher gekommen.
- `nvidia-smi`: beide Karten (24 GB und 16 GB) belegt, zusammen rund 31 GB bei drei gleichzeitigen Anfragen.
- In Codena unter Einstellungen > KI das Profil „Qwen3-Coder 30B“ öffnen: LLM-Context-Länge 65536; dann
  „Fähigkeiten prüfen“ (Werkzeuge, Argumente, Ergebnisnutzung sollten grün sein).

Läuft der Chat zu langsam oder fehlt Speicher, in `.env` `OLLAMA_NUM_PARALLEL` und `INFERENCE_MAX_CONCURRENCY`
gemeinsam senken (z. B. auf 2) und `docker compose up -d --no-build` erneut ausführen.

## Danach

- Ports 3000 und 8000 sind ohne TLS auf allen Schnittstellen offen: Firewall und Reverse Proxy davor, bevor echte
  Daten hineinkommen (`docs/DEPLOYMENT.md`, Abschnitt TLS im Codena-Repository).
- Pakete in GitHub (Profil > Packages), dieses Repository und beide Tokens nach dem Rollout löschen; die Images
  enthalten den Anwendungscode.
