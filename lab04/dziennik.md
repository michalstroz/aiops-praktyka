# lab04 — dziennik

| # | Bramka / krok | Co złapała (albo co poprawiłem sam) | Poprawka |
|---|---|---|---|
| 1 | `kubectl apply --dry-run=server -f k8s/`, `trivy config k8s/` | Nic: obie bramki bez błędów (trivy: 0 misconfigurations w obu plikach). Ale żadna nie sprawdza, czy selektory PDB i NetworkPolicy trafiają w pody | Sprawdziłem w klastrze po `apply`: `kubectl get pdb` → `ALLOWED DISRUPTIONS 1` (selektor trafił w oba pody orders-api), `setup/check.sh` → 11/11 („zamówienie przez web” = orders-api łączy się z Postgresem mimo NetworkPolicy) |
| 2 | `kubectl diff -f k8s/` | Status PDB w diffie miał same zera (`currentHealthy: 0`, `disruptionsAllowed: 0`). To nie błąd: diff pokazuje obiekt, zanim kontroler PDB policzy pody | Brak. Po `apply` kontroler wyliczył status: `ALLOWED DISRUPTIONS 1` |
| 3 | `terraform plan` (krok 5) | `Plan: 1 to add`: Terraform chce utworzyć NetworkPolicy, która już istnieje z kroku 4 (`kubectl apply`). Stan jest pusty, więc Terraform nie wie o obiekcie. `apply` skończyłby się błędem `already exists` | Bez `apply`. Przejęcie istniejącego obiektu: blok `import` (`id = "michal/kantyna-postgres-allow-orders-api"`), potem jedno źródło prawdy, czyli usunięcie YAML-a z procesu kubectl |
