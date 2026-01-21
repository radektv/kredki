# 🎨 KREDKI

**KREDKI** to narzędzie open‑source do **lokalnego audytu bezpieczeństwa i analizy kontekstu**
dla systemów Linux.

Projekt służy do wykrywania **poświadczeń, sekretów i wrażliwych danych**
(hasła, tokeny API, klucze prywatne itp.)
**z uwzględnieniem realnego ryzyka ich ekspozycji**.

KREDKI zostały zaprojektowane jako narzędzie:
- ✅ audytowe i defensywne
- ✅ w pełni lokalne (brak ruchu wychodzącego)
- ✅ bezpieczne dla produkcji (read‑only)
- ❌ nie są pentestem
- ❌ nie wykonują exploitów
- ❌ nie modyfikują systemu

> ⚠️ Uruchamiaj wyłącznie na systemach, których jesteś właścicielem  
> lub na które posiadasz wyraźną zgodę.

---

## 🆕 Wersja 1.8 (aktualna)

### Najważniejsze zmiany w v1.8

- ✅ **Stabilne generowanie raportów HTML**
- ✅ Pełne wypełnianie HTML danymi systemowymi:
  OS, kernel, CPU, RAM, uptime, sieć, użytkownicy, dyski
- ✅ Odporność na brakujące zmienne (`set -u` safe)
- ✅ Naprawione ciche przerywanie skryptu (`set -e`)
- ✅ Spójna wersja widoczna w:
  - CLI
  - raporcie TXT
  - raporcie HTML
- ✅ Raport HTML czytelny w Chrome / Firefox / Brave

**Wersja:** `1.8`

---

## 📸 Zrzuty ekranu

Pliki znajdują się w katalogu `screenshots/` i są renderowane bezpośrednio przez GitHub.

### 🖥️ Interfejs CLI
![CLI UI](screenshots/ui.png)

### 📊 Podsumowanie skanu
![Summary](screenshots/summary.png)

### 🔍 Wyniki skanowania
![Results](screenshots/results.png)

### 🧭 Breakdown kontekstu ryzyka
![Context breakdown](screenshots/context_breakdown.png)

### 📄 Raport HTML
![HTML report](screenshots/html_report.png)

---

## 🚀 Dlaczego KREDKI?

Większość skanerów odpowiada tylko na pytanie:

> **„Czy gdzieś jest sekret?”**

KREDKI odpowiadają na pytanie istotniejsze:

> **„Jak duże jest ryzyko tego sekretu w tym konkretnym miejscu?”**

| Lokalizacja | Ocena ryzyka |
|------------|--------------|
| `/root/.env` | 🔴 WYSOKIE |
| `/etc/app/config.yml` | 🔴 WYSOKIE |
| `/home/user/.env` | 🟠 ŚREDNIE |
| `/tmp/test.txt` | 🟡 NISKIE |

---

## ✨ Główne funkcje

- Rekursywne skanowanie systemu plików
- Bardzo szybkie wyszukiwanie (`ripgrep`)
- **Kontekst bezpieczeństwa**: HIGH / MEDIUM / LOW
- Profile środowisk: `default`, `prod`, `dev`, `ctf`
- **Safe Production Mode**
- Redakcja sekretów (safe to share)
- Raport TXT + **raport HTML klasy audytowej**
- Obsługa `.kredkiignore`
- Brak agentów, brak chmury, brak telemetrii

---

## 📦 Wymagania

- Linux
- `bash` ≥ 4.x
- `ripgrep`

```bash
sudo apt install -y ripgrep
```

---

## 📁 Instalacja

```bash
git clone https://github.com/radektv/kredki.git
cd kredki
chmod +x kredki-ui.sh
```

---

## ▶️ Przykładowe użycie (CLI Cookbook)

Poniżej znajdują się **praktyczne scenariusze**, bezpośrednio zgodne z `--help`.

---

### 🔍 Podstawowy skan wybranych katalogów

```bash
./kredki-ui.sh --paths /etc,/home
```

**Zastosowanie:** szybki audyt konfiguracji systemu i użytkowników.

---

### 📄 Generowanie raportu HTML

```bash
./kredki-ui.sh --paths /etc,/home --html
```

Tworzy:
- raport TXT
- raport HTML obok pliku TXT

---

### 🛡️ Bezpieczny skan produkcyjny (rekomendowane)

```bash
./kredki-ui.sh --profile prod --safe --html
```

**Cechy:**
- tylko operacje read‑only
- konserwatywne limity
- bezpieczne dla produkcji

---

### 🧭 Kontekst per plik (mniej szumu)

```bash
./kredki-ui.sh --context-mode file
```

Jeden wpis = jeden plik, niezależnie od liczby dopasowań.

---

### 🧾 Raport z redakcją sekretów

```bash
./kredki-ui.sh --html --redact --context-mode file
```

**Idealne do:**
- udostępniania raportu
- zgłoszeń audytowych
- zespołów zewnętrznych

---

### 🤖 Tryb automatyczny / CI

```bash
./kredki-ui.sh --non-interactive --html --context-mode file
```

Bez promptów, gotowe do pipeline CI/CD.

---

### 📂 Nadpisanie ścieżek + limity

```bash
./kredki-ui.sh \
  --paths /etc,/var,/srv \
  --max-filesize 5M \
  --html
```

---

### 🚫 Ignorowanie plików i katalogów

```bash
./kredki-ui.sh --ignore-file /root/.kredkiignore
```

---

## 📄 Raporty

Generowane pliki:

- `kredki_found_<HOST>_<TIMESTAMP>.txt`
- `kredki_found_<HOST>_<TIMESTAMP>.html`
- `*.redacted.txt`

Podgląd w terminalu:
```bash
less -R kredki_found_*.txt
w3m kredki_found_*.html
```

---

## 🔐 Bezpieczeństwo raportów

Raporty mogą zawierać dane wrażliwe.

Zalecane uprawnienia:
```bash
chmod 600 kredki_found_*
```

---

## 🧭 Czym KREDKI NIE są

- ❌ pentestem
- ❌ narzędziem do eskalacji uprawnień
- ❌ skanerem sieci
- ❌ narzędziem SaaS
- ❌ systemem telemetrycznym

---

## 📜 Licencja

MIT License — używaj odpowiedzialnie.

---

## 🧩 Filozofia projektu

> *„Wyniki bezpieczeństwa bez kontekstu to tylko szum.”*

KREDKI skupiają się na **realnym ryzyku**, a nie na liczbie trafień.
