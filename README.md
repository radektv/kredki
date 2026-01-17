# 🎨 KREDKI – Fast Secret Scanner for Linux (v1.0)

**KREDKI** to szybki, rekursywny skaner sekretów dla systemów Linux, napisany w Bash.
Projekt jest przeznaczony do **audytów bezpieczeństwa, pentestów, CTF oraz przeglądu konfiguracji serwerów**.

Skanowanie odbywa się **rekursywnie**, z wykorzystaniem `ripgrep`, z podsumowaniem:
- czasu skanowania **per katalog**
- liczby trafień **per katalog**
- łącznego czasu i liczby wykrytych sekretów

> ⚠️ Uruchamiaj wyłącznie na systemach, do których masz prawo dostępu.

---

## 🚀 Features

- 🔍 Rekursywne skanowanie całych drzew katalogów
- ⚡ Bardzo szybkie wyszukiwanie (`ripgrep`)
- 📊 Statystyki per katalog (czas + trafienia)
- 🧠 Automatyczne wykorzystanie CPU
- 🖥️ Czytelny interfejs TUI (spinner, banner, summary)
- 📄 Bezpieczne pliki wynikowe (`chmod 600`)
- 🐧 Linux / Bash native

---

## 📸 Screenshots

### UI
![UI](screenshots/ui.png)

### Results
![Results](screenshots/results.png)

---

## 📦 Wymagania

- `bash` >= 4.x  
- `ripgrep` (`rg`)  
- `coreutils`

### Instalacja zależności (Debian / Ubuntu / Kali)

```bash
sudo apt update
sudo apt install -y ripgrep
```

---

## 📁 Instalacja

**Zalecany katalog:**

```bash
sudo mkdir -p /local/kredki
sudo chown -R $USER:$USER /local/kredki
cd /local/kredki
```

Pliki projektu:

```text
/local/kredki
├── kredki.sh
├── kredki-ui.sh
├── patterns.txt
├── README.md
├── README_EN.md
└── screenshots/
```

Uprawnienia:

```bash
chmod +x kredki.sh kredki-ui.sh
```

---

## ▶️ Uruchomienie

```bash
./kredki-ui.sh
```

---

## 📊 Zakres skanowania

Domyślnie skanowane katalogi (rekursywnie):

- `/etc`
- `/home`
- `/root`
- `/opt`
- `/srv`
- `/var`

Wykluczenia:
- `.git`
- `node_modules`
- `vendor`
- pliki binarne, `.zip`, `.bin`

---

## 📄 Wyniki

Tworzony jest plik:

```text
kredki_found_YYYY-MM-DD_HH-MM-SS.txt
```

Zawiera:
- nagłówki per katalog
- czas skanowania
- liczbę trafień
- surowe wyniki `ripgrep`

Podgląd:

```bash
less -R kredki_found_*.txt
```

---

## 🔐 Bezpieczeństwo

- Wyniki mogą zawierać dane wrażliwe
- Zalecane uruchamianie jako `root`
- Narzędzie nie wysyła danych na zewnątrz

---

## 📜 Licencja

Projekt udostępniony „as is”.
Użycie wyłącznie do celów legalnych i testów bezpieczeństwa.
