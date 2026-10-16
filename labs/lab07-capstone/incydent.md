# lab07 — dziennik incydentu (namespace `michal`)

Zgłoszenie: menu ładuje się bardzo wolno, czasem błąd.
Czas: CEST (UTC+2), pt 16.10.2026. Kolumna „Hipoteza” mówi, kto ją postawił: AI (Claude Code) albo ja.

| Godzina | Hipoteza (AI / ja) | Komenda / zapytanie | Wynik | Status |
|---|---|---|---|---|
| 14:25 | — (wykrycie, AI zbiera objawy) | `kubectl -n michal get deploy,sts,pods -o wide` | `kantyna-orders-api` 0/2 Ready (pody Running, 0 restartów, wiek 71 min). web, payments 2/2, worker 1/1, postgres 1/1 | objaw |
| 14:25 | — (wykrycie, AI) | `kubectl -n michal get events --sort-by=.lastTimestamp` | Oba pody orders-api: `Readiness probe failed: Get ".../readyz": context deadline exceeded` | objaw |
| 14:26 | — (wykrycie, AI) | `kubectl -n michal logs deploy/kantyna-orders-api --since=15m` | Co 5 s `WARNING Readiness check failed`, `error: couldn't get a connection after 30.00 sec` | objaw |
| 14:26 | — (wykrycie, AI) | PromQL: `max by (pod) (db_pool_connections_in_use{namespace="michal"}) / max by (pod) (db_pool_size{namespace="michal"})`, ostatnie 90 min, krok 5 min | Oba pody orders-api: 0 do 14:16, 1 (100% puli) o 14:21 | objaw |
| 14:27 | — (wykrycie, AI) | PromQL: `up{namespace="michal"}` | Wszystkie targety = 1, scrape działa (dane na dashboardzie będą) | objaw |
| 14:28 | — (wykrycie, ja) | `setup/check.sh michal` | **8/11**. ❌ orders-api gotowe 0/2 · ❌ menu przez web (`exit code 1`) · ❌ zamówienie przez web (`exit code 1`). Reszta ✅, w tym „Service kantyna-orders-api: ma endpointy” | objaw |
| 14:29 | — (wykrycie, AI) | `kubectl -n michal get endpointslices -l kubernetes.io/service-name=kantyna-orders-api` (adres + `conditions.ready`) | Oba endpointy `ready=false`. ✅ w `check.sh` dla endpointów orders-api jest fałszywie pozytywne: skrypt sprawdza tylko, czy adres istnieje | objaw |
| 14:29 | — (wykrycie, AI) | `kubectl -n michal get pods -l app.kubernetes.io/name=orders-api` (warunek `Ready`, `lastTransitionTime`) | NotReady od 14:20:01 (`l97fm`) i 14:20:32 (`6nzln`) | objaw |
| 14:31 | H1 (AI): ostatnia zmiana konfiguracji (runbook KantynaDBPoolExhausted, krok 4) | `kubectl -n michal get cm kantyna-flags -o jsonpath='{.data.flags\.json}'` + `.metadata.managedFields`; `helm -n michal history kantyna` | `orders-api.db_pool_leak: true`, `slow_menu_query: true`. Polem `data.flags.json` zarządza `kubectl-patch`, ostatni zapis o 14:17:42. Release Helm bez zmian od 15.10 10:37 (rev 3) | potwierdzone |
| 14:31 | H1 (AI) | `labs/lab06-agent-runbook/audit.jsonl` (`get_flags` przed `reset_flag` o 13:44:52) | O 13:44 obie flagi miały wartość `false`, więc zmieniono je między 13:44:52 a 14:17:42. Kto to zrobił, nie wiemy: `managedFields` podaje tylko narzędzie | potwierdzone |
| 14:32 | H1a (AI): `db_pool_leak` wycieka połączenia | kod: `app/orders-api/app/main.py:147-151`, `app/orders-api/app/db.py:63-70` | 30% żądań `GET /api/menu` pobiera połączenie z puli i go nie zwraca. Połączenia wracają do puli dopiero przy jej zamknięciu, czyli przy restarcie poda. **Wyłączenie flagi nie zwolni puli** | potwierdzone (mechanizm) |
| 14:32 | H1a (AI) | PromQL: `max by (pod) (db_pool_connections_in_use{namespace="michal", pod=~"kantyna-orders-api-5c79.*"})`, 14:10–14:33, krok 1 min | 0 do 14:19. `l97fm`: 10 o 14:20, `6nzln`: 10 o 14:21. Od tej pory stale 10 (rozmiar puli), choć ruch od 14:21 = 0. Zgodnie z runbookiem to wyciek, a nie efekt obciążenia | potwierdzone |
| 14:32 | H1a (AI): pełna pula daje „wolno” i błędy ze zgłoszenia | PromQL: `histogram_quantile(0.95, sum by (route, le) (rate(http_request_duration_seconds_bucket{namespace="michal", job="kantyna-orders-api", route=~"/api/menu\|/api/orders"}[2m])))`, 14:17–14:23 | p95 5–41 ms do 14:20, potem 10 s (górny kubełek histogramu; żądanie czeka do 30 s na połączenie). 14:21–14:22: 4× `GET /api/menu` → 500 | potwierdzone |
| 14:32 | H1b (AI): `slow_menu_query` włącza N+1 w menu | Tempo: `{ resource.service.name = "orders-api" && resource.k8s.namespace.name = "michal" && span.http.route = "/api/menu" }`, 14:15–14:30 | Do 14:18:40: 4 spany, ~1,5 ms na żądanie. Od 14:18:52: 24 spany, 12–16 ms (kod: `app/orders-api/app/db.py:120-130`, osobne zapytanie dla każdej pozycji menu) | potwierdzone: ~10× wolniej, ale to wciąż milisekundy, nie sekundy |
| 14:32 | H2 (AI): wzrost ruchu przeciąża pulę | PromQL: `sum by (route, status) (increase(http_requests_total{namespace="michal", job="kantyna-orders-api", route=~"/api/.*"}[1m]))`; `kubectl -n michal get deploy kantyna-loadgen` (`managedFields`, etykiety, env) | Przed 14:17 nie było ruchu na `/api/` (same sondy). loadgen powstał o 14:17:40 (`kubectl-client-side-apply`, etykieta `aiops/lab=lab07`, `PEAK_RPS=3`). Szczyt ok. 1,4 req/s. Pula nie opada przy zerowym ruchu, więc to nie obciążenie | wyzwalacz, nie przyczyna |
| 14:33 | H3 (AI): awaria Postgresa albo payments | `kubectl -n michal logs sts/kantyna-postgres --since=30m`; `kubectl -n michal get pods` | Postgres: same checkpointy, bez `too many connections`. payments 2/2, 0 restartów | wykluczone |
| 14:33 | (AI) dlaczego nie było alertu | `kubectl -n michal get prometheusrule`; `helm -n michal get values kantyna` | `No resources found`. W release `prometheusRule.enabled: false`, więc reguły KantynaDBPoolExhausted / HighLatencyP95 w michal nie istnieją. Wykrycie dopiero po zgłoszeniu użytkowników | potwierdzone (luka) |
| 14:36 | (AI) repo a klaster | `helm template kantyna app/deploy/helm/kantyna -s templates/configmap-flags.yaml` vs `kubectl get cm kantyna-flags`, `diff -u` | Poza dwiema flagami różni się też format: `"error_rate": 0.0` zamiast `0` (pozostałość po resecie w lab06) i brak końcowego `\n`. Przestawienie samych flag nadal dałoby w pipeline `conflict with "kubectl-patch"` | potwierdzone |
| 14:38 | Mitygacja (AI proponuje, ja zatwierdzam) | `kubectl patch cm kantyna-flags` (treść = render z repo) | AI nie mogło tego wykonać: auto mode zablokował zmianę („Modify Shared Resources”). Komendy uruchomiłem sam | — |
| 14:42:00 | Mitygacja 1/2 (ja) | `kubectl -n michal patch configmap kantyna-flags --type merge --patch-file patch-flags-z-repo.json` | `configmap/kantyna-flags patched`; ConfigMapa = render z repo, bajt w bajt (`diff -q`) | wykonane |
| 14:42:07 | Mitygacja 2/2 (ja) | `kubectl -n michal rollout restart deploy/kantyna-orders-api` | nowy ReplicaSet `5c794c696b`, pody Ready o 14:42:13 i 14:42:20 → **usługa przywrócona 14:42:20** | wykonane |
| 14:43 | Weryfikacja mitygacji (AI) | `kubectl get deploy kantyna-orders-api`; PromQL `db_pool_connections_in_use` (nowe pody); Tempo `/api/menu` od 14:42 | 2/2 Ready; pula 0/10; menu: 4 spany, ~1,5 ms (jak przed 14:18) | potwierdzone |
| 14:46 | Weryfikacja mitygacji (ja) | `setup/check.sh michal` | **SUKCES: 11/11**, ale jeszcze przed wdrożeniem z pipeline'u (o 14:46 trwa build orders-api), więc to wynik po mitygacji, a nie po naprawie | potwierdzone |
| 14:49 | Weryfikacja naprawy (ja) | `setup/check.sh michal` (pody orders-api na obrazie `:6f99184d…`) | **SUKCES: 11/11** po wdrożeniu z pipeline'u | potwierdzone |

**Początek wpływu:** 14:20:32 CEST (oba pody orders-api NotReady). Wcześniej użytkownicy zgłaszali wolne menu, ale tego jeszcze nie zmierzyliśmy.
**Wykrycie:** 14:25 CEST.

**Objawy:**
- orders-api nie przechodzi readiness, więc żaden endpoint Service `kantyna-orders-api` nie jest gotowy, a web nie ma dokąd przekazać `/api/`. Menu i zamówienia przez web nie działają (`check.sh`)
- pula połączeń do bazy w orders-api zajęta w 100% na obu podach (od ok. 14:21)
- `/readyz` czeka 30 s na połączenie z puli i przekracza 3-sekundowy timeout sondy

## Komunikat 1 (krok 2)

Szkic AI według `docs/prompts/komunikat-incydentu.md` (odbiorca: zespoły, kanał zespołu):

> Kantyna nie wyświetla menu i nie przyjmuje zamówień, a każda próba kończy się błędem. Od ok. 14:20 te funkcje nie działają wcale, a wcześniej użytkownicy zgłaszali wolne ładowanie menu. Dotyczy to wszystkich użytkowników: w tej chwili nie da się zamówić obiadu. Pracujemy nad przywróceniem działania usługi; przyczyna nie jest jeszcze potwierdzona. Kolejna informacja o 15:00 albo wcześniej, jeśli usługa wróci.

Wersja wysłana o 14:31: **szkic AI zaakceptowany bez zmian** (sprawdziłem, że każde zdanie ma pokrycie w dzienniku: `check.sh`, 0/2 Ready, NotReady od 14:20). Następna aktualizacja: 15:00.

## Diagnoza (krok 3)

Szablon `docs/prompts/diagnoza.md`, runbooki `KantynaDBPoolExhausted.md` i `KantynaHighLatencyP95.md`. Same komendy tylko do odczytu. Hipotezy postawiło AI, a dowody są w tabeli wyżej.

| Hipoteza | Dowód | Komenda weryfikująca | Werdykt |
|---|---|---|---|
| `db_pool_leak=true` wycieka połączenia, pula 10/10, `/readyz` przekracza czas, 0/2 Ready | flaga w ConfigMapie; pula 10/10 bez względu na ruch; kod `main.py:147-151` | `db_pool_connections_in_use`, `managedFields` ConfigMapy | **przyczyna główna** |
| `slow_menu_query=true`: N+1 w `GET /api/menu` | 24 spany zamiast 4, ~10× dłużej | Tempo, `http.route="/api/menu"` | **współprzyczyna** (wolniejsze menu, więcej zapytań na połączenie) |
| wzrost ruchu | ruch ~1 req/s, pula nie opada przy zerowym ruchu | `http_requests_total` | wyzwalacz, nie przyczyna |
| Postgres / payments | brak błędów, pody zdrowe | logi Postgresa, `get pods` | wykluczone |

Luki w systemie (do post-mortem):
- konfigurację produkcyjną (flagi) zmieniono ręcznie (`kubectl patch`), z pominięciem repo i pipeline'u; klaster rozjechał się z repo i nikt tego nie zauważył
- w namespace `michal` nie ma reguł alertów (`prometheusRule.enabled: false`), więc pełna pula nie wywołała alertu
- `check.sh` uznaje endpointy `ready=false` za poprawne (fałszywie pozytywny wynik)

Odtworzona oś czasu (CEST):

| Godzina | Zdarzenie | Źródło |
|---|---|---|
| 13:14:02 | rollout restart orders-api (lab06), nowy ReplicaSet `5c79c659f` | `managedFields` deploymentu (`kubectl-rollout`), adnotacja `restartedAt` |
| 13:44:52 | agent z lab06 resetuje `error_rate`; `db_pool_leak` i `slow_menu_query` = `false` | `audit.jsonl` |
| 14:17:40 | powstaje Deployment `kantyna-loadgen` i zaczyna się ruch na `/api/` | `managedFields`, `http_requests_total` |
| 14:17:42 | ConfigMapa `kantyna-flags` zmieniona: `db_pool_leak=true`, `slow_menu_query=true` | `managedFields` (`kubectl-patch`) |
| 14:18:40–14:18:52 | flagi docierają do podów: menu przechodzi na N+1 | Tempo (4 → 24 spany) |
| 14:20:00–14:21:00 | pula 10/10 na obu podach | `db_pool_connections_in_use` |
| 14:20:01 / 14:20:32 | pody orders-api NotReady; **od 14:20:32 menu i zamówienia nie działają** | warunek `Ready` podów |
| 14:25 | wykrycie (zgłoszenie użytkowników, `kubectl`) | dziennik |
| 14:28 | `check.sh` 8/11 | dziennik |
| 14:31 | komunikat 1 na kanał zespołu | dziennik |

## Komunikat 2 (po mitygacji)

Szkic AI:

> Od 14:42 Kantyna znowu działa: menu się wyświetla, a zamówienia są przyjmowane. Między ok. 14:20 a 14:42 nie dało się zamówić obiadu, a wcześniej menu ładowało się wolno. Przyczyną była błędna zmiana konfiguracji; wycofaliśmy ją i ponownie uruchomiliśmy usługę. Do zamknięcia incydentu obserwujemy działanie i wdrażamy trwałą poprawkę. Kolejna informacja przy zamknięciu incydentu, najpóźniej o 15:30.

Wersja wysłana o 14:45: **szkic AI zaakceptowany bez zmian**. Następna aktualizacja przy zamknięciu, najpóźniej o 15:30.

## Naprawa (krok 4)

- Commit: `6f99184dffa71afcd3dcce8becccfb15e453dfbf`, „lab07: runbook KantynaDBPoolExhausted — najpierw flaga, potem restart; flagi przez repo”. Diff przejrzany przed commitem (`git diff`)
- Przebieg: https://github.com/michalstroz/aiops-praktyka/actions/runs/38902732865 (start 14:45:05), wynik: **✅ success** (koniec 14:47:30; testy, 4 buildy i wdrożenie z `helm upgrade`, `rollout status`, sprawdzeniem obrazów i smoke testem zielone)
- Zmiana na klastrze: `helm upgrade` nakłada ConfigMapę flag z repo (treść identyczna z mitygacją, nie powinno być konfliktu) i wdraża obrazy `:6f99184d…`
- Po wdrożeniu (AI, 14:47): `helm history` → rev 4 (14:46:37); wszystkie 4 deploymenty na obrazie `:6f99184d…`, Ready; flagi == render z repo
- `managedFields` ConfigMapy po wdrożeniu: `helm` (Apply) znów zarządza `data.flags.json`, **wspólnie** z `kubectl-patch` (Update). Konfliktu nie było, bo wartość była identyczna. Ryzyko (do sprawdzenia, nie potwierdzone): przy następnej zmianie flag w repo `helm upgrade` może dostać konflikt z `kubectl-patch`, który nadal współzarządza polem

## Weryfikacja (krok 5)

Okno obserwacji: **14:48:12–14:53:12** (5 min po wdrożeniu rev 4). Zapytania AI w Prometheusie, krok 1 min:

| Metryka | Zapytanie | W oknie | Przed incydentem | Status |
|---|---|---|---|---|
| Pula DB | `max by (pod) (db_pool_connections_in_use{namespace="michal", job="kantyna-orders-api"})` | 0 na obu podach (`df7cf6d4f-*`) przez całe okno | 0 | ✅ |
| Odsetek 5xx `/api/` | `(sum(rate(http_requests_total{…, route=~"/api/.*", status=~"5.."}[1m])) or vector(0)) / sum(rate(http_requests_total{…, route=~"/api/.*"}[1m]))` | 0 przez całe okno | 0 | ✅ |
| p95 `/api/menu` | `histogram_quantile(0.95, sum by (route, le) (rate(http_request_duration_seconds_bucket{…}[2m])))` | 4,7–5,0 ms | 5–22 ms | ✅ |
| p95 `/api/orders` | jw. | 24–25 ms | 25–41 ms | ✅ |
| Ruch obsłużony | `sum by (route, status) (increase(http_requests_total{…, route=~"/api/.*"}[5m]))` o 14:53:12 | menu 220×200, orders 100×201, search 33×200, order 10×200, 0 błędów | — | ✅ |

Zastrzeżenie: „przed incydentem” to krótki okres ruchu z loadgena (14:17:40–14:20). Wcześniej na `/api/` nie było ruchu w ogóle, więc nie ma dłuższej linii bazowej.

`setup/check.sh` po naprawie: 11/11 (14:49). **Krok 5 spełniony.**

## Wpływ (pomiar po incydencie)

| Godzina | Kto | Zapytanie | Wynik |
|---|---|---|---|
| 14:54 | AI | `round(sum by (exported_endpoint, status) (increase(loadgen_requests_total{namespace="michal"}[22m])))` na 14:42:20 (okno 14:20:20–14:42:20) | **Zamówienia (`orders_create`): 0 udanych, 391 nieudanych** (344 `error` + 47 `timeout`). Menu: 9 udanych, 865 nieudanych (773 `error` + 92 `timeout`). Wyszukiwanie: 1 udane, 139 nieudanych. Podgląd zamówienia: 0 udanych, 64 nieudane. Razem ok. 1460 nieudanych żądań na 10 udanych. `loadgen_dropped_total` = 0 |

`timeout` to żądania czekające na połączenie z pełnej puli (to „wolno” ze zgłoszenia). `error` to żądania odrzucone, gdy żaden pod nie był Ready. Liczby pochodzą z `increase()`, więc są przybliżone.

## Komunikat 3 (zamknięcie)

Szkic AI, wysłany o 14:58: **zaakceptowany bez zmian**:

> Incydent z 14:20–14:42 jest zamknięty: Kantyna działa stabilnie, a trwała poprawka została wdrożona o 14:47. Nie dało się wtedy złożyć zamówienia; jeśli ktoś został bez obiadu, prosimy o ponowne zamówienie. Podsumowanie z wnioskami udostępnimy po analizie.

**Zamknięcie incydentu:** 14:58 CEST. Post-mortem: [`post-mortem.md`](post-mortem.md).
