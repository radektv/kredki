# 🎨 KREDKI – Fast Secret Scanner for Linux (v1.0)

**KREDKI** is a fast, recursive secret scanner for Linux systems written in Bash.
Designed for **security audits, pentesting, CTFs, and server configuration reviews**.

The scan runs **recursively** and provides:
- per-directory scan time
- per-directory hit counts
- total scan duration and total findings

> ⚠️ Run only on systems you own or have explicit permission to scan.

---

## 🚀 Features

- 🔍 Recursive filesystem scanning
- ⚡ High-performance search (`ripgrep`)
- 📊 Per-directory statistics (time + hits)
- 🧠 Automatic CPU utilization
- 🖥️ Clean TUI (spinner, banner, summary)
- 📄 Secure output files (`chmod 600`)
- 🐧 Native Linux / Bash tool

---

## 📸 Screenshots

### UI
![UI](screenshots/ui.png)

### Results
![Results](screenshots/results.png)

---

## 📦 Requirements

- `bash` >= 4.x  
- `ripgrep` (`rg`)  
- `coreutils`

### Install dependencies (Debian / Ubuntu / Kali)

```bash
sudo apt update
sudo apt install -y ripgrep
```

---

## 📁 Installation

**Recommended directory:**

```bash
sudo mkdir -p /local/kredki
sudo chown -R $USER:$USER /local/kredki
cd /local/kredki
```

Project files:

```text
/local/kredki
├── kredki.sh
├── kredki-ui.sh
├── patterns.txt
├── README.md
├── README_EN.md
└── screenshots/
```

Permissions:

```bash
chmod +x kredki.sh kredki-ui.sh
```

---

## ▶️ Usage

```bash
./kredki-ui.sh
```

---

## 📊 Scan Scope

Default recursive scan paths:

- `/etc`
- `/home`
- `/root`
- `/opt`
- `/srv`
- `/var`

Exclusions:
- `.git`
- `node_modules`
- `vendor`
- binary files, `.zip`, `.bin`

---

## 📄 Results

A result file is created:

```text
kredki_found_YYYY-MM-DD_HH-MM-SS.txt
```

Contains:
- per-directory headers
- scan duration
- hit counts
- raw `ripgrep` matches

View results:

```bash
less -R kredki_found_*.txt
```

---

## 🔐 Security Notes

- Output may contain sensitive data
- Running as `root` is recommended
- Tool does not transmit data externally

---

## 📜 License

Provided “as is”.
Use only for legal security testing purposes.
