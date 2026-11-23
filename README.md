# Doctus Pilot – Begleitdateien (pilot-20261122)

Alles, was die Deployment-Maschine neben den drei Images braucht. Images und Stand: Commit `05e599e`,
Datenmodell 1.13.0, Migrationen bis `0051` (laufen beim ersten Start automatisch).

| Datei | Zweck |
|---|---|
| `docker-compose.yml`, `docker-compose.gpu.yml` | Dienste; die GPU-Datei gibt Ollama die Grafikkarten |
| `.env.example` | Vorlage der Einstellungen (nie eine ausgefüllte `.env` einchecken) |
| `config/features.json` | Funktionsschalter |
| `pull-images.sh` | Images aus `ghcr.io` ziehen und lokal benennen |
| `setup-env.sh` | `.env` einmalig für den Pilot erzeugen (GPU, `qwen3-coder:30b`, 64k, 3 parallel) |
| `generate_diagnostics.py` | Diagnosepaket bei Problemen |
| `test-remote-inference.sh`, `check_remote_inference.py` | Nur für einen getrennten Modellserver |

## Voraussetzungen

- Ubuntu 24.04 (oder vergleichbar), Docker mit Compose v2, `git`, `openssl`.
- NVIDIA-Treiber und NVIDIA Container Toolkit: `docker info | grep -i nvidia` muss die Runtime zeigen.
- Internet zu `ghcr.io`, Docker Hub (PostgreSQL, Valkey, Ollama per Digest) und `ollama.com` (Modelle, ~20 GB).
- Lese-Token (classic, `read:packages`; `repo`, falls dieses Repository damit geklont wird).
- Betrieb als normaler Nutzer (z. B. `doctusops`) ohne sudo: Ein Administrator nimmt ihn einmalig in die Gruppe
  `docker` auf (`usermod -aG docker doctusops`, danach neu anmelden); `docker ps` muss dann ohne sudo gehen.
  Die Gruppe `docker` ist gleichwertig zu root auf dem Host. Git, Docker und NVIDIA-Toolkit muss der
  Administrator vorab installieren.

## Ablauf

```sh
git clone https://github.com/maxdedecke/doctus-deploy-1.git ~/doctus && cd ~/doctus

docker login ghcr.io -u maxdedecke                  # Passwort: Lese-Token
./pull-images.sh
docker logout ghcr.io

./setup-env.sh <server-adresse>                      # genau einmal; legt .env an
cp .env /sicherer/ort/doctus.env                     # sofort sichern: ohne MASTER_ENCRYPTION_KEY ist alles unlesbar

docker compose up -d --no-build
docker exec doctus-ollama ollama pull bge-m3
docker exec doctus-ollama ollama pull qwen3-coder:30b     # ~19 GB
docker compose logs backend-api | grep -A3 "Erster Start" # Admin-Passwort, wird nur einmal angezeigt
docker compose ps
curl -fsS http://localhost:8000/health && curl -fsS http://localhost:8000/version
```

`--no-build` ist Pflicht: Die Compose-Datei enthält Build-Abschnitte für Verzeichnisse, die es hier nicht gibt.

Die Container laufen intern als root; was sie unter `data/` und `repos/` anlegen, gehört daher root. Ohne sudo
löscht man es über einen Container, z. B. `docker run --rm -v "$PWD/data:/d" alpine rm -rf /d/logs`.

## Prüfen

- `docker exec doctus-ollama ollama ps` nach der ersten Chatfrage: `PROCESSOR` muss „100% GPU“ zeigen, `CONTEXT`
  65536. Steht dort ein CPU-Anteil, ist das Modell nicht ganz in den Grafikspeicher gekommen.
- `nvidia-smi`: beide Karten (24 GB und 16 GB) belegt, zusammen rund 31 GB bei drei gleichzeitigen Anfragen.
- In Doctus unter Einstellungen > KI das Profil „Qwen3-Coder 30B“ öffnen: LLM-Context-Länge 65536; dann
  „Fähigkeiten prüfen“ (Werkzeuge, Argumente, Ergebnisnutzung sollten grün sein).

Läuft der Chat zu langsam oder fehlt Speicher, in `.env` `OLLAMA_NUM_PARALLEL` und `INFERENCE_MAX_CONCURRENCY`
gemeinsam senken (z. B. auf 2) und `docker compose up -d --no-build` erneut ausführen.

## Danach

- Ports 3000 und 8000 sind ohne TLS auf allen Schnittstellen offen: Firewall und Reverse Proxy davor, bevor echte
  Daten hineinkommen (`docs/DEPLOYMENT.md`, Abschnitt TLS im Doctus-Repository).
- Pakete in GitHub (Profil > Packages), dieses Repository und beide Tokens nach dem Rollout löschen; die Images
  enthalten den Anwendungscode.
