# 🎨 KREDKI
## Fast Secret Scanner for Linux (Context-Aware)

**KREDKI** is an open‑source, context‑aware secret scanner for Linux systems.  
It helps identify **passwords, API tokens, private keys and credentials**
stored in files, focusing on **WHERE the secret is located**, not exploitation.

> ⚠️ Scan only systems you own or have explicit permission to audit.

---

## 🚀 Why KREDKI?

Most tools only answer **“is there a secret?”**  
KREDKI answers **“how dangerous is it?”**

A password in `/root/.env` is not the same risk as one in `/tmp/test.txt`.

---

## ✨ Key Features

- 🔍 Recursive filesystem scanning
- ⚡ Ultra-fast search using **ripgrep**
- 🧭 **Security Context**: HIGH / MEDIUM / LOW
- 📂 Per-directory scan statistics (time & hits)
- 🧩 Environment **profiles** (default / prod / dev / ctf)
- 🛡️ **Safe Production Mode**
- 🧾 **Redaction** for share-safe reports
- 📄 **Security-ready HTML reports**
- 🖥️ Clean TUI output (banner, spinner, summary)

---

## 🧠 Security Context Explained

| Level | Meaning | Examples |
|----|----|----|
| 🔴 HIGH | Critical system secrets | `/root`, `/etc`, `.env`, `.git-credentials` |
| 🟠 MEDIUM | Application data | `/var`, `/home`, `/srv` |
| 🟡 LOW | Temporary files | `/tmp`, `/var/tmp` |

> Context is inferred **only from file location**, never from exploitation.

---

## 📸 Screenshots

| What | Preview |
|----|----|
| CLI UI | [screenshots/ui.png](screenshots/ui.png) |
| Scan Summary | [screenshots/summary.png](screenshots/summary.png) |
| HTML Report | [screenshots/html_report.png](screenshots/html_report.png) |
| Context Breakdown | [screenshots/context_breakdown.png](screenshots/context_breakdown.png) |

---

## 📦 Requirements

- Linux
- bash ≥ 4.x
- ripgrep

```bash
sudo apt install -y ripgrep
```

---

## 📁 Installation

```bash
git clone https://github.com/radektv/kredki.git
cd kredki
chmod +x kredki-ui.sh
```

---

## ▶️ Basic Usage

```bash
./kredki-ui.sh
```

---

## 🧪 Practical Examples (Cookbook)

### 🔍 Scan selected directories
```bash
./kredki-ui.sh --paths /etc,/home
```

### 🛡️ Production-safe scan
```bash
./kredki-ui.sh --profile prod --safe
```

### 📄 Generate HTML report
```bash
./kredki-ui.sh --html
```

### 🧭 Context per FILE (recommended)
```bash
./kredki-ui.sh --context-mode file
```

### 🧾 Redacted report (safe to share)
```bash
./kredki-ui.sh --html --redact
```

### 🤖 CI / automation
```bash
./kredki-ui.sh --non-interactive --html --context-mode file
```

---

## 📄 Reports

Generated files:
- `kredki_found_YYYY-MM-DD_HH-MM-SS.txt`
- `kredki_found_YYYY-MM-DD_HH-MM-SS.html`
- `*.redacted.txt`

CLI preview:
```bash
less -R kredki_found_*.txt
w3m kredki_found_*.html
```

---

## 🔐 Security Notes

- Reports may contain sensitive data
- HTML is **redacted by default**
- Recommended file permissions:
```bash
chmod 600 kredki_found_*
```

---

## 📜 License

MIT License – use responsibly.
