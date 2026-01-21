# 🎨 KREDKI

**KREDKI** to narzędzie open-source do **lokalnego audytu bezpieczeństwa i analizy kontekstu** dla systemów Linux.

Projekt służy do wykrywania **poświadczeń, sekretów i wrażliwych danych**
(w tym haseł, tokenów API, kluczy prywatnych),
**z uwzględnieniem realnego ryzyka ich ekspozycji**.

KREDKI:
- ❌ nie wykonują exploitów
- ❌ nie modyfikują systemu
- ❌ nie wysyłają danych poza host
- ✅ działają wyłącznie lokalnie
- ✅ są przeznaczone do audytu i przeglądów bezpieczeństwa

> ⚠️ Uruchamiaj wyłącznie na systemach, których jesteś właścicielem
> lub na które posiadasz wyraźną zgodę.

---

## 🆕 Wersja 1.8 (aktualna)

### Najważniejsze zmiany w v1.8

- ✅ Stabilne generowanie raportów HTML (naprawione problemy `set -euo`)
- ✅ Pełne wypełnianie HTML danymi systemowymi (OS, kernel, CPU, RAM, uptime)
- ✅ Odporność na brakujące zmienne (`nounset safe`)
- ✅ Naprawione ciche przerwania skryptu
- ✅ Spójna wersja w CLI, TXT i HTML
- ✅ Czytelny, audytowy raport HTML

**Wersja:** `1.8`

---

## 📸 Zrzuty ekranu

Poniższe obrazy pochodzą z katalogu [`screenshots/`](screenshots) i są renderowane bezpośrednio przez GitHub:

### 🖥️ Interfejs CLI
![CLI UI](screenshots/ui.png)

### 📊 Podsumowanie skanu
![Scan summary](screenshots/summary.png)

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

KREDKI odpowiadają:

> **„Jak duże jest ryzyko tego sekretu w tym miejscu?”**

| Lokalizacja | Ryzyko |
|------------|--------|
| `/root/.env` | 🔴 WYSOKIE |
| `/etc/app/config.yml` | 🔴 WYSOKIE |
| `/home/user/.env` | 🟠 ŚREDNIE |
| `/tmp/test.txt` | 🟡 NISKIE |

---

## ✨ Główne funkcje

- Rekursywne skanowanie systemu plików
- Bardzo szybkie wyszukiwanie (ripgrep)
- Ocena ryzyka: HIGH / MEDIUM / LOW
- Profile środowisk (`default`, `prod`, `dev`, `ctf`)
- Safe Production Mode
- Redakcja sekretów
- Raport HTML klasy audytowej
- Brak agentów i połączeń sieciowych

---

## 📦 Wymagania

- Linux
- bash ≥ 4.x
- ripgrep

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

## ▶️ Przykładowe użycie

```bash
./kredki-ui.sh --paths /etc,/home --html
```

---

## 📄 Raporty

- TXT – pełny raport tekstowy
- HTML – raport audytowy
- *.redacted.txt – wersje bezpieczne do udostępniania

---

## 🔐 Bezpieczeństwo raportów

Raporty mogą zawierać dane wrażliwe.

Zalecane uprawnienia:
```bash
chmod 600 kredki_found_*
```

---

## 📜 Licencja

MIT License

---

## 🧩 Filozofia projektu

> *„Wyniki bezpieczeństwa bez kontekstu to tylko szum.”*

KREDKI skupiają się na **realnym ryzyku**, a nie na liczbie trafień.
