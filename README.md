# 🎨 KREDKI
## Szybki skaner sekretów dla systemów Linux (świadomy kontekstu bezpieczeństwa)

**KREDKI** to narzędzie open‑source do wykrywania **haseł, tokenów API,
kluczy prywatnych oraz innych sekretów** zapisanych w plikach na systemach Linux.

W przeciwieństwie do klasycznych skanerów, KREDKI koncentruje się na
**kontekście bezpieczeństwa**, a nie na exploitacji czy eskalacji uprawnień.

> ⚠️ Uruchamiaj wyłącznie na systemach, które posiadasz lub masz wyraźną zgodę skanować.

---

## 🚀 Dlaczego KREDKI?

Większość narzędzi odpowiada tylko na pytanie:  
**„Czy gdzieś istnieje sekret?”**

KREDKI odpowiada na ważniejsze pytanie:  
**„Jak bardzo to jest niebezpieczne?”**

Ten sam sekret w:
- `/root/.env` → 🔴 **wysokie ryzyko**
- `/tmp/test.txt` → 🟡 **niskie ryzyko**

---

## ✨ Główne funkcje

- 🔍 Rekursywne skanowanie systemu plików
- ⚡ Bardzo szybkie wyszukiwanie (ripgrep)
- 🧭 **Kontekst bezpieczeństwa**: HIGH / MEDIUM / LOW
- 📂 Statystyki per katalog (czas skanowania i liczba trafień)
- 🧩 Profile środowisk (`default`, `prod`, `dev`, `ctf`)
- 🛡️ **Tryb bezpieczny (Safe Production Mode)**
- 🧾 **Redakcja sekretów** – raporty bezpieczne do udostępniania
- 📄 **Raport HTML** gotowy do audytu bezpieczeństwa
- 🖥️ Czytelny interfejs CLI (banner, spinner, podsumowanie)

---

## 🧠 Kontekst bezpieczeństwa – jak to działa?

KREDKI **nie próbuje łamać systemu**.  
Poziom ryzyka określany jest **wyłącznie na podstawie lokalizacji pliku**.

| Poziom | Znaczenie | Przykłady |
|------|-----------|----------|
| 🔴 HIGH | Krytyczne sekrety systemowe | `/root`, `/etc`, `.env`, `.git-credentials` |
| 🟠 MEDIUM | Dane aplikacyjne | `/var`, `/home`, `/srv` |
| 🟡 LOW | Pliki tymczasowe | `/tmp`, `/var/tmp` |

---

## 📸 Zrzuty ekranu

- Interfejs CLI → [screenshots/ui.png](screenshots/ui.png)
- Podsumowanie skanu → [screenshots/summary.png](screenshots/summary.png)
- Raport HTML → [screenshots/html_report.png](screenshots/html_report.png)
- Breakdown kontekstu → [screenshots/context_breakdown.png](screenshots/context_breakdown.png)

---

## 📦 Wymagania

- Linux
- bash ≥ 4.x
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

## ▶️ Podstawowe użycie

```bash
./kredki-ui.sh
```

---

## 🧪 Przykłady użycia (CLI Cookbook)

### 🔍 Skan wybranych katalogów
```bash
./kredki-ui.sh --paths /etc,/home
```

### 🛡️ Bezpieczny skan produkcyjny
```bash
./kredki-ui.sh --profile prod --safe
```

### 📄 Generowanie raportu HTML
```bash
./kredki-ui.sh --html
```

### 🧭 Kontekst per PLIK (mniej szumu)
```bash
./kredki-ui.sh --context-mode file
```

### 🧾 Raport z redakcją sekretów (do udostępnienia)
```bash
./kredki-ui.sh --html --redact
```

### 🤖 Automaty / CI
```bash
./kredki-ui.sh --non-interactive --html --context-mode file
```

---

## 📄 Raporty

Generowane pliki:
- `kredki_found_YYYY-MM-DD_HH-MM-SS.txt`
- `kredki_found_YYYY-MM-DD_HH-MM-SS.html`
- `*.redacted.txt`

Podgląd w terminalu:
```bash
less -R kredki_found_*.txt
w3m kredki_found_*.html
```

---

## 🔐 Bezpieczeństwo

- Raporty mogą zawierać dane wrażliwe
- Raport HTML jest domyślnie **zredagowany**
- Zalecane uprawnienia:
```bash
chmod 600 kredki_found_*
```

---

## 📜 Licencja

MIT License – używaj odpowiedzialnie.
