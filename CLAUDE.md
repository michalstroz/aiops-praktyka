# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Czym jest to repo

Repo szkoleniowe Sages „AIOps w praktyce”. Całość (laby, docs, README, komentarze) jest po polsku — zachowuj język. Ćwiczenia kręcą się wokół aplikacji **Kantyna** (zamawianie obiadów) działającej na EKS (eu-central-1).

- `app/` — Kantyna: kod serwisów, chart Helm, runbooki, k6 (opis: `app/README.md`)
- `labs/` — laby lab01–lab07 (README: cel, kroki, warunek SUKCES); `labs/lab06-agent-runbook/` ma działającego agenta (`agent.py`) i `zepsuj.sh`
- `docs/` — materiały tematyczne (`.md` + `architektura.html`), szablony promptów w `docs/prompts/`
- `setup/` — przygotowanie stanowiska; `setup/check.sh [namespace]` sprawdza zdrowie Kantyny (oczekiwane `SUKCES: 11/11`)
- `aws/` i `awscliv2.zip` w rootcie to nieśledzone artefakty instalatora AWS CLI — nie commituj

## Komendy (z katalogu `app/`)

```bash
docker compose up -d --build        # lokalnie: UI :8088, API :8000/docs  (make compose-up / compose-down)
make test                           # orders-api + payments
make test-orders-api                # cd orders-api && uv run pytest -q
cd orders-api && uv run pytest tests/test_api.py::nazwa_testu   # pojedynczy test
make test-payments                  # go test w kontenerze golang:1.23
make helm-lint && make helm-template
make ecr-login && make build push VERSION=1.0.0 [VARIANT=receipt-v2]
```

Ruch i k6: `docker compose --profile loadgen up -d loadgen`, scenariusze w `load/k6/` (przykłady w `app/README.md`).

## Wersje narzędzi

Wersje, z którymi sprawdzono repo (lokalnie, macOS arm64): kubectl v1.37.1, helm v4.3.0, aws-cli 2.38.0, k8sgpt 0.4.40.
Python 3.12 (orders-api, worker), Go 1.23 (payments, test w kontenerze `golang:1.23`), PostgreSQL 17.
Sprawdzenie: `kubectl version --client`, `helm version --short`, `aws --version`.

## Architektura

`web` (nginx, proxy `/api/`) → `orders-api` (FastAPI, Python 3.12) → `payments` (Go) / PostgreSQL / SQS → `worker` (konsument SQS, paragony do S3). `loadgen` generuje ruch o profilu dobowym. Obserwowalność: Prometheus (`/metrics` w każdym serwisie, `ServiceMonitor`), logi JSON → Loki, OTLP → Tempo; `trace_id` łączy logi i trace'y.

Kolejność w `POST /api/orders`: walidacja → payments (`/pay`; odmowa = brak zapisu) → transakcja w Postgresie → SQS (tylko gdy ustawiono `QUEUE_URL`). Lokalnie nie ma SQS/S3, więc worker tylko czeka.

Rzeczy wymagające czytania wielu plików:
- **Flagi runtime / wstrzykiwanie awarii**: każdy serwis ma własny store flag (np. `orders-api/app/flags.py`, `payments/flags.go`, `worker/app/flags.py`) czytający env + plik JSON (`FLAGS_FILE`; w klastrze ConfigMap `templates/configmap-flags.yaml`, lokalnie `deploy/local/flags.json`), przeładowywany cyklicznie bez restartu; wartości z pliku mają pierwszeństwo. Laby psują i naprawiają Kantynę przez te flagi (`error_rate`, `db_pool_leak`, `slow_menu_query`, `memory_leak_mb_per_min`, …).
- **Alerty ↔ runbooki**: reguły w `deploy/helm/kantyna/templates/prometheusrule.yaml` odpowiadają 1:1 plikom `app/runbooks/Kantyna*.md`; zmieniając jedno, zaktualizuj drugie.
- **Warianty builda** (`APP_VARIANT`: `stable`, `receipt-v2`, `menu-v2`) i `VERSION` trafiają do `/version`, `kantyna_build_info` i tagów obrazów; `orders-api/Dockerfile.legacy` to osobna ścieżka buildu (`make legacy-build`).
- Uprawnienia do SQS/S3: EKS Pod Identity dla ServiceAccountów `kantyna-orders-api` i `kantyna-worker`.

## Bezpieczeństwo i zasady pracy

- `.claude/settings.json`: odczyt kubectl (get/describe/logs/top) dozwolony; `set/patch/edit/rollout/apply` wymagają zgody; `get secret*`, `delete`, `exec` zablokowane. Nie obchodź tych reguł.
- Klaster jest wspólny — działaj tylko w swoim namespace.
- `app/.env` zawiera fałszywe sekrety; do modelu nie wysyłaj prawdziwych kluczy ani danych osobowych.
- Hipotezy i komendy od AI weryfikuj przed zatwierdzeniem (zasada szkolenia). Laby używają LiteLLM przez `OPENAI_API_KEY` / `OPENAI_ENDPOINT`.
