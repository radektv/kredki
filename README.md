# 🎨 KREDKI
### Fast Secret Scanner for Linux

**KREDKI** to szybkie, bezpieczne i czytelne narzędzie do wykrywania
**sekretów, haseł, tokenów i kluczy** w systemach Linux.

Projekt skupia się na **security context**, a nie exploitach — pokazuje
*gdzie* leżą potencjalnie niebezpieczne dane i *jak bardzo* są ryzykowne.

> ⚠️ Uruchamiaj wyłącznie na systemach, które posiadasz lub masz zgodę skanować.

---

## ✨ Główne cechy

- 🔍 Rekursywne skanowanie systemu plików
- ⚡ Bardzo szybkie wyszukiwanie (`ripgrep`)
- 🧭 Security Context: HIGH / MEDIUM / LOW
- 📂 Statystyki per katalog (czas + liczba trafień)
- 🧾 Redaction – bezpieczne raporty do share
- 📄 HTML report gotowy do audytu
- 🧩 Profile środowisk (default / prod / dev / ctf)
- 🛡️ Safe Production Mode
- 🖥️ Czytelny TUI

---

## 📦 Wymagania

- Linux
- bash >= 4.x
- ripgrep

```bash
sudo apt install -y ripgrep
```

---

## ▶️ Przykłady

```bash
./kredki-ui.sh --html --context-mode file
./kredki-ui.sh --profile prod --safe
```

---

## 📜 Licencja
MIT
