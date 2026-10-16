Jesteś SRE. Środowisko: Kubernetes/EKS (eu-central-1), aplikacja Kantyna.
Objaw: $ARGUMENTS
Już sprawdziłem: nic, zaczynam od zera.
Zadanie: podaj 3 najbardziej prawdopodobne hipotezy, od najbardziej prawdopodobnej.
Ograniczenia: proponuj tylko komendy read-only. Nie proponuj jeszcze poprawki.
Jeśli brakuje danych, napisz, jakiej komendy potrzebujesz, zamiast zgadywać.
Format: tabela | hipoteza | dowód z danych | komenda weryfikująca |.
Zbierz dane komendami read-only (kubectl get/describe/logs). Zredaguj sekrety przed analizą.

- Pola „Dane” już nie ma, bo agent zbiera dane sam, a plik podajesz w argumentach.
- Wersje klastra i komponentu agent może sprawdzić sam. W szablonie możesz je zostawić jako polecenie, np. „wersję sprawdź przez kubectl version”.
- Zamiast tego promptu wpisz własny „najlepszy prompt” z części B, jeśli różnił się od szablonu. README prosi o ten najlepszy.