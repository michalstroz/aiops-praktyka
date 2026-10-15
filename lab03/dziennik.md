# lab03 — dziennik

| # | Objaw (krok, komunikat) | Hipoteza (AI / ja) | Jak sprawdziłem | Poprawka | Status |
|---|---|---|---|---|---|
| 1 | Brak błędów: pierwszy przebieg na `main` (run 38721251694, commit `e77f9ad`) zielony | — | `gh run view 38721251694`; `kubectl get deploy -n michal` pokazuje obrazy `…/michal/kantyna/<serwis>:e77f9ad9…`; smoke test: `/version` zwraca SHA commita | — | ✅ |

## Sugestia AI, której nie wdrożyłem

**Sugestia:** zamienić w `helm upgrade` flagę `--reuse-values` na `--reset-then-reuse-values`.

**Argument AI:** `--reuse-values` bierze wartości z poprzedniego release i pomija domyślne wartości z `values.yaml` w repo. Gdy do charta dojdzie nowy klucz, upgrade go nie zobaczy, a szablon dostanie pustą wartość. `--reset-then-reuse-values` bierze świeże domyślne wartości z charta i nakłada na nie wartości z release.

**Dlaczego nie wdrożyłem:**
- Opis pipeline'u w labie wprost wymaga `--reuse-values`.
- Dziś ryzyko nie występuje. Wszystkie 240 kluczy z `app/deploy/helm/kantyna/values.yaml` jest w wartościach release `kantyna` (rev 2), więc `--reuse-values` niczego nie gubi.
- Zmiana flagi zmienia sposób liczenia wartości przy każdym deployu. Wolę ją zrobić świadomie, gdy zmieni się chart, i wtedy porównać wynik `helm template` przed i po.

**Kiedy wrócić:** przy pierwszej zmianie `values.yaml`, która dodaje nowy klucz.

## Checklista: wersje Pythona i Go

- **Akcje:** najnowsze tagi z dnia pisania workflow. Runner `ubuntu-24.04` to obecny `ubuntu-latest`.
- **Python 3.12** (w przebiegu 3.12.3): wymóg labu i ta sama linia co w Dockerfile'ach (`python:3.12-slim`). Najnowszy jest 3.15.0, a 3.12 dostaje już tylko poprawki bezpieczeństwa.
- **Go 1.23** (w przebiegu go1.23.12): CI bierze wersję z `app/payments/go.mod`, tak samo jak `payments/Dockerfile` (`golang:1.23`), więc testuje to, co działa w klastrze. Najnowsze jest Go 1.27.2. Wsparcie mają tylko dwie ostatnie linie (1.26 i 1.27), więc 1.23 nie dostaje już poprawek bezpieczeństwa.
- **Decyzja:** CI zostaje zgodne z aplikacją, bo samo podbicie wersji w CI oznaczałoby testowanie innego Go niż na produkcji. Podbicie Go do 1.27 to osobna zmiana aplikacji: `go.mod`, `payments/Dockerfile` i `golang:1.23` w `Makefile`, potem `make test-payments` i przebieg pipeline'u.
