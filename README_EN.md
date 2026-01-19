# 🎨 KREDKI
## Fast Secret Scanner for Linux (Security Context Aware)

**KREDKI** is an open‑source tool for detecting **passwords, API tokens,
private keys and other secrets** stored in files on Linux systems.

Unlike classic scanners, KREDKI focuses on **security context**, not exploitation.

> ⚠️ Scan only systems you own or are explicitly authorized to audit.

---

## 🚀 Why KREDKI?

Most tools only answer:  
**“Is there a secret somewhere?”**

KREDKI answers the more important question:  
**“How risky is it?”**

The same secret in:
- `/root/.env` → 🔴 **high risk**
- `/tmp/test.txt` → 🟡 **low risk**

---

## ✨ Features

- 🔍 Recursive filesystem scanning
- ⚡ High‑performance search (ripgrep)
- 🧭 **Security Context**: HIGH / MEDIUM / LOW
- 📂 Per‑directory statistics (scan time and hits)
- 🧩 Environment profiles (`default`, `prod`, `dev`, `ctf`)
- 🛡️ **Safe Production Mode**
- 🧾 Secret redaction for safe sharing
- 📄 **Security‑ready HTML reports**
- 🖥️ Clean CLI interface (banner, spinner, summary)

---

## 🧠 Security Context – how it works

KREDKI does **not exploit systems**.  
Risk is inferred **solely from file location**.

| Level | Meaning | Examples |
|----|--------|---------|
| 🔴 HIGH | Critical system secrets | `/root`, `/etc`, `.env`, `.git-credentials` |
| 🟠 MEDIUM | Application data | `/var`, `/home`, `/srv` |
| 🟡 LOW | Temporary files | `/tmp`, `/var/tmp` |

---

## 📸 Screenshots

- CLI UI → [screenshots/ui.png](screenshots/ui.png)
- Scan summary → [screenshots/summary.png](screenshots/summary.png)
- HTML report → [screenshots/html_report.png](screenshots/html_report.png)
- Context breakdown → [screenshots/context_breakdown.png](screenshots/context_breakdown.png)

---

## 📦 Requirements

- Linux
- bash ≥ 4.x
- `ripgrep`

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

## ▶️ Basic usage

```bash
./kredki-ui.sh
```

---

## 🧪 Usage examples (CLI Cookbook)

### 🔍 Scan selected directories
```bash
./kredki-ui.sh --paths /etc,/home
```

### 🛡️ Production‑safe scan
```bash
./kredki-ui.sh --profile prod --safe
```

### 📄 Generate HTML report
```bash
./kredki-ui.sh --html
```

### 🧭 Context per FILE (less noise)
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

## 🔐 Security notes

- Reports may contain sensitive data
- HTML report is **redacted by default**
- Recommended permissions:
```bash
chmod 600 kredki_found_*
```

---

## 📜 License

MIT License – use responsibly.
