# Post-mortem: Kantyna niedostępna, pula połączeń orders-api wyczerpana (pt 16.10.2026)

Formuła bez szukania winnych (blameless). Czas: CEST. Źródło: dziennik [`incydent.md`](incydent.md).

**Kto co napisał:**
- tekst bez oznaczeń to **szkic AI** (Claude Code, 14:55, według `docs/prompts/post-mortem.md`); każde zdanie ma pokrycie w wierszu dziennika
- **⚠️ AI, poza dziennikiem:** AI dopisało to bez dowodu w dzienniku. Do sprawdzenia: zostawić z dowodem albo usunąć
- **✏️ ja:** moje poprawki i uzupełnienia; zmiany zapisuję też w „Rejestrze poprawek” na końcu

## Podsumowanie

Od 14:20:32 do 14:42:20 Kantyna nie wyświetlała menu i nie przyjmowała zamówień. W ConfigMapie `kantyna-flags` ręcznie (`kubectl patch`, 14:17:42), z pominięciem repo i pipeline'u, włączono dwie flagi awarii orders-api: `db_pool_leak` i `slow_menu_query`. Wyciek połączeń zapełnił pulę bazy (10/10) na obu podach. Sonda `/readyz` zaczęła przekraczać czas i oba pody wypadły z ruchu. Mitygacja: przywrócenie flag z repo i restart orders-api. Naprawa: wdrożenie z pipeline'u (commit `6f99184`), które ustawiło konfigurację z repo.

## Wpływ

- **Czas:** całkowita niedostępność menu i zamówień przez ok. 22 min (14:20:32–14:42:20). Od początku wpływu do wykrycia minęło ok. 4,5 min (14:25), od wykrycia do przywrócenia ok. 17 min.
- **Zakres:** wszyscy użytkownicy: 0 z 2 podów orders-api Ready, `check.sh` 8/11 (menu i zamówienie przez web ❌).
- **Skala** (loadgen, okno 14:20:20–14:42:20, wartości przybliżone):

  | Operacja | Udane | Nieudane (`error` + `timeout`) |
  |---|---|---|
  | złożenie zamówienia | 0 | 391 (344 + 47) |
  | menu | 9 | 865 (773 + 92) |
  | wyszukiwanie w menu | 1 | 139 (127 + 12) |
  | podgląd zamówienia | 0 | 64 (55 + 9) |

- **Objaw ze zgłoszenia „menu ładuje się bardzo wolno”:** w metrykach widać go w 14:20–14:21. p95 `/api/menu` i `/api/orders` ≥ 10 s, bo żądania czekały do 30 s na połączenie z pełnej puli. Przed 14:20 p95 wynosiło 5–41 ms.

## Oś czasu

| Godzina | Zdarzenie | Źródło |
|---|---|---|
| 13:44:52 | Ostatni znany dobry stan flag: `db_pool_leak` i `slow_menu_query` = `false` (agent z lab06 resetuje `error_rate`, też przez `kubectl patch`) | `labs/lab06-agent-runbook/audit.jsonl` |
| 14:17:40 | Powstaje Deployment `kantyna-loadgen` i zaczyna się ruch na `/api/` (wcześniej tylko sondy) | `managedFields`, `http_requests_total` |
| 14:17:42 | `kantyna-flags`: `db_pool_leak=true`, `slow_menu_query=true` (`kubectl-patch`) | `managedFields` ConfigMapy |
| 14:18:40–14:18:52 | Flagi docierają do podów: `GET /api/menu` przechodzi na N+1 (4 → 24 spany) | Tempo |
| 14:20:00–14:21:00 | Pula połączeń 10/10 na obu podach i już nie spada | `db_pool_connections_in_use` |
| 14:20:01 / 14:20:32 | Pody orders-api NotReady. **Początek całkowitej niedostępności** | warunek `Ready` podów |
| 14:20–14:21 | p95 ≥ 10 s, 4× `GET /api/menu` → 500 | `http_request_duration_seconds`, `http_requests_total` |
| 14:25 | **Wykrycie** (zgłoszenie użytkowników, `kubectl`) | dziennik |
| 14:28 | `check.sh` 8/11 | dziennik |
| 14:31 | Komunikat 1 na kanale zespołu | dziennik |
| 14:31–14:33 | Diagnoza: flagi, wyciek, N+1. Wykluczone: Postgres, payments, przeciążenie ruchem | dziennik, wiersze H1–H3 |
| 14:36 | Porównanie repo z klastrem: oprócz flag różni się format (`0.0` vs `0`, końcowe `\n`) | `helm template` + `diff` |
| 14:38 | AI nie może zmienić ConfigMapy (auto mode: „Modify Shared Resources”). Komendy przejmuje człowiek | dziennik |
| 14:42:00 | Mitygacja 1/2: flagi = render z repo, bajt w bajt | `kubectl patch`, `diff -q` |
| 14:42:07–14:42:20 | Mitygacja 2/2: restart orders-api, pody Ready. **Usługa przywrócona** | `rollout restart`, warunek `Ready` |
| 14:45 | Komunikat 2. Push commita `6f99184` uruchamia pipeline | dziennik, GitHub Actions |
| 14:46:37 | `helm upgrade` rev 4 bez konfliktu, obrazy `:6f99184d…` | `helm history` |
| 14:47:30 | Pipeline zielony ([przebieg 38902732865](https://github.com/michalstroz/aiops-praktyka/actions/runs/38902732865)) | GitHub Actions |
| 14:48:12–14:53:12 | Okno obserwacji: pula 0, 5xx 0%, p95 menu ~5 ms, orders ~24 ms. `check.sh` 11/11 (14:49) | Prometheus, `check.sh` |

## Przyczyna źródłowa

**Mechanizm (fakty):**
1. `db_pool_leak=true`: 30% żądań `GET /api/menu` pobiera połączenie z puli i go nie zwraca (`main.py:147-151`). Połączenia wracają do puli dopiero przy jej zamknięciu (`db.py:63-70`), dlatego samo wyłączenie flagi nie wystarczyło i potrzebny był restart.
2. Pula 10/10 sprawia, że `/readyz` czeka 30 s na połączenie przy 3-sekundowym timeoucie sondy. Oba pody przechodzą w NotReady, a Service nie ma gotowych endpointów.
3. `slow_menu_query=true` (współprzyczyna): N+1 w menu (osobne zapytanie dla każdej pozycji, 24 spany zamiast 4), ~10× dłużej (12–16 ms zamiast ~1,5 ms). Sama ta flaga nie tłumaczy sekund opóźnienia.

**Luki w systemie i procesie:**
- **Konfigurację produkcyjną można zmienić z pominięciem repo.** `kubectl patch` na ConfigMapie flag nie przechodzi przez review ani pipeline i nic nie wykrywa rozjazdu z repo. Rozjazd istniał już przed incydentem: reset w lab06 o 13:44:52 zostawił `0.0` zamiast `0` i ręcznego właściciela pola.
- **Brak alertów w namespace.** `prometheusRule.enabled: false`, więc KantynaDBPoolExhausted i KantynaHighLatencyP95 nie istnieją. Incydent wykryto dopiero dzięki użytkownikom.
- **Narzędzie kontrolne daje fałszywie pozytywny wynik.** `check.sh` zalicza endpointy z `ready=false`.

## Co zadziałało

- Runbook KantynaDBPoolExhausted (krok 4, „Recent changes”) od razu skierował diagnozę na `kantyna-flags`.
- `managedFields` i audyt agenta z lab06 zawęziły chwilę zmiany do okna 13:44:52–14:17:42 bez zgadywania.
- Liczba spanów w Tempo potwierdziła N+1, ale też pokazała, że to milisekundy. Dzięki temu nie uznaliśmy `slow_menu_query` za główną przyczynę.
- Porównanie repo z klastrem przed mitygacją pozwoliło ustawić flagi bajt w bajt jak w repo. `helm upgrade` w pipeline przeszedł bez `conflict with "kubectl-patch"` i bez `--force-conflicts`.
- Kolejność mitygacji (najpierw flaga, potem restart) wynikała z analizy kodu. Restart przy włączonej fladze zapchałby pulę ponownie.
- Zabezpieczenie: auto mode nie pozwolił AI zmienić wspólnej konfiguracji. Komendę po przejrzeniu uruchomił człowiek.

## Co nie zadziałało

- Brak alertu. Wykrycie po ok. 4,5 min, i to dzięki użytkownikom.
- `check.sh` zgłaszał „Service kantyna-orders-api: ma endpointy” ✅ przy 0 gotowych podach.
- Rozjazd konfiguracji po lab06 nie został naprawiony przez repo. Pole flag miało ręcznego właściciela jeszcze przed incydentem.
- Przekazanie komendy człowiekowi wydłużyło mitygację o ok. 4 min (14:38 → 14:42).
- ⚠️ AI, poza dziennikiem: dashboard z lab05 (`michal-lab05-kantyna`) ma na sztywno `namespace="demo"` i nie ma panelu puli DB ani p95 `/api/menu`, więc w czasie incydentu był bezużyteczny. Dowód: opis dashboardu w Grafanie, sprawdzony przez AI ok. 14:27, ale niewpisany do dziennika.
- ⚠️ AI, poza dziennikiem: AI raz uruchomiło `kubectl apply --dry-run=client` (ok. 14:35) bez pytania o zgodę. Na klastrze nic się nie zmieniło, ale polecenie nie zostało zatrzymane do zatwierdzenia, choć `.claude/settings.json` każe pytać o `kubectl apply`.

## Akcje

Zrobione: runbook KantynaDBPoolExhausted uzupełniony o sprawdzanie `managedFields`, kolejność „flaga, potem restart” i zasadę „flagi przez repo” (commit `6f99184`).

Propozycje AI (✏️ ja: zatwierdź albo zmień, wpisz właściciela i termin):

| # | Akcja | Rodzaj | Luka | Właściciel | Termin |
|---|---|---|---|---|---|
| 1 | Włączyć reguły alertów Kantyny w namespace uczestnika (`prometheusRule.enabled: true`) po uzgodnieniu z prowadzącym routingu we wspólnym Alertmanagerze | wykrywanie | brak alertów | | |
| 2 | Wykrywanie rozjazdu: zaplanowany job w CI porównujący render chartu z klastrem (np. `helm upgrade --dry-run=server` / `kubectl diff --server-side`) albo alert, gdy `kantyna-flags` ma właściciela innego niż `helm` | zapobieganie | ręczne zmiany konfiguracji | | |
| 3 | Flagi zmieniamy tylko przez PR do values. Odebrać ludziom i agentom `patch` na ConfigMapy w namespace (RBAC); wyjątek awaryjny tylko z wpisem w dzienniku i commitem wyrównującym | zapobieganie | ręczne zmiany konfiguracji | | |
| 4 | `setup/check.sh`: liczyć tylko endpointy z `conditions.ready=true` | wykrywanie | fałszywie pozytywny wynik | | |
| 5 | Sprawdzić i usunąć współwłasność `kubectl-patch` pola `data.flags.json`, zanim ktoś zmieni flagi w repo; inaczej pipeline może dostać konflikt | ryzyko | rozjazd konfiguracji | | |
| 6 | Dashboard: zmienna `namespace`, panele „pula DB” i „p95 `/api/menu`” | wykrywanie | brak widoku podczas incydentu | | |

## Pytania otwarte

- Kto i dlaczego zmienił flagi o 14:17:42? `managedFields` podaje tylko narzędzie (`kubectl-patch`). Do sprawdzenia: logi audytu API EKS, jeśli są włączone. Zbieżność z utworzeniem loadgena (14:17:40, etykieta `aiops/lab=lab07`) sugeruje scenariusz labu. To hipoteza AI, niepotwierdzona.
- Czy „wolne menu” ze zgłoszenia występowało przed 14:20? Metryki tego nie pokazują (p95 5–41 ms). Spowolnienie widać dopiero w 14:20–14:21.
- Czy `/readyz` powinno zależeć od wspólnej puli DB? Dziś pełna pula wyłącza wszystkie repliki naraz, więc zamiast degradacji jest całkowita niedostępność. To hipoteza AI do dyskusji z właścicielem orders-api.
- Czy po wspólnej własności pola (Helm + `kubectl-patch`) następna zmiana flag przez repo przejdzie w pipeline bez konfliktu? (akcja 5)

## Rejestr poprawek (✏️ ja)

| Sekcja | Było (AI) | Jest (ja) | Dlaczego |
|---|---|---|---|
| | | | |
