# Notatki lab01b

## Trzy różnice między `zly.yaml` a `dobry.yaml`

1. **Hasło do bazy.** `zly.yaml` używa wymyślonego Secretu `db-credentials` i zmiennej `PGPASSWORD`. `dobry.yaml` bierze `DB_USER` i `DB_PASSWORD` z prawdziwego Secretu z charta (`kantyna-db`), więc nic nie jest wpisane jawnie.
2. **Probes.** `zly.yaml` sprawdza tylko, czy port jest otwarty (`tcpSocket`). `dobry.yaml` odpytuje aplikację przez `httpGet` na `/healthz` i `/readyz`, więc Kubernetes widzi, czy aplikacja faktycznie działa.
3. **Wolumeny i konfiguracja.** `zly.yaml` ma `readOnlyRootFilesystem: true`, ale nie ma zapisywalnego `/tmp`, ConfigMapy z flagami ani zmiennych `PAYMENTS_URL`, `DATABASE_URL` i `FLAGS_FILE`, więc aplikacja by się nie uruchomiła. `dobry.yaml` ma to wszystko, tak jak chart.

## Czego walidator nie sprawdził

Walidator (`kubectl apply --dry-run=client`) przepuścił oba pliki, bo sprawdza tylko schemat. Nie sprawdza, czy limity mają sens. Limit pamięci `384Mi` w `dobry.yaml` może być za mały, bo flaga `memory_leak_mb_per_min` potrafi go przekroczyć i pod zostanie zabity (OOMKilled). Walidator nie sprawdza też, czy Secret `kantyna-db` i ConfigMap `kantyna-flags` istnieją ani czy obraz jest w ECR.
