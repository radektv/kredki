# 🎨 KREDKI

**KREDKI** is an open-source tool for **local security auditing and context-aware analysis**
of Linux systems.

It is designed to identify **credentials, secrets, and sensitive data**
(passwords, API tokens, private keys, etc.)
**together with the real risk of their exposure**.

KREDKI is intentionally built as:
- ✅ an audit & defensive tool
- ✅ fully local (no outbound traffic)
- ✅ safe for production (read-only)
- ❌ not a pentest tool
- ❌ no exploitation
- ❌ no system modification

> ⚠️ Run **only** on systems you own  
> or where you have explicit authorization.

---

## 🆕 Version 1.8 (current)

### What’s new in v1.8

- ✅ **Stable HTML report generation**
- ✅ HTML reports fully populated with system context:
  OS, kernel, CPU, RAM, uptime, network, users, disks
- ✅ Safe handling of unset variables (`set -u` safe)
- ✅ Fixed silent script termination (`set -e` issues)
- ✅ Unified version visible in:
  - CLI
  - TXT report
  - HTML report
- ✅ HTML reports readable in Chrome / Firefox / Brave

**Version:** `1.8`

---

## 📸 Screenshots

Images are stored in the `screenshots/` directory and rendered directly by GitHub.

### 🖥️ CLI Interface
![CLI UI](screenshots/ui.png)

### 📊 Scan Summary
![Summary](screenshots/summary.png)

### 🔍 Scan Results
![Results](screenshots/results.png)

### 🧭 Risk Context Breakdown
![Context breakdown](screenshots/context_breakdown.png)

### 📄 HTML Report
![HTML report](screenshots/html_report.png)

---

## 🚀 Why KREDKI?

Most secret scanners answer only one question:

> **“Is there a secret somewhere?”**

KREDKI answers a more important one:

> **“How risky is this secret in this exact location?”**

| Location | Risk level |
|---------|------------|
| `/root/.env` | 🔴 HIGH |
| `/etc/app/config.yml` | 🔴 HIGH |
| `/home/user/.env` | 🟠 MEDIUM |
| `/tmp/test.txt` | 🟡 LOW |

---

## ✨ Key Features

- Recursive filesystem scanning
- Very fast pattern matching (`ripgrep`)
- **Security context scoring**: HIGH / MEDIUM / LOW
- Environment profiles: `default`, `prod`, `dev`, `ctf`
- **Safe Production Mode**
- Secret redaction (safe to share)
- TXT + **audit-grade HTML report**
- `.kredkiignore` support
- No agents, no cloud, no telemetry

---

## 📦 Requirements

- Linux
- `bash` ≥ 4.x
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

## ▶️ Usage Examples (CLI Cookbook)

All examples below are **fully aligned with `--help` output**.

---

### 🔍 Basic scan of selected directories

```bash
./kredki-ui.sh --paths /etc,/home
```

Use case: quick audit of system and user configuration.

---

### 📄 Generate HTML audit report

```bash
./kredki-ui.sh --paths /etc,/home --html
```

Generates:
- TXT report
- HTML report next to TXT

---

### 🛡️ Safe production scan (recommended)

```bash
./kredki-ui.sh --profile prod --safe --html
```

Characteristics:
- read-only
- conservative limits
- production-safe

---

### 🧭 File-level context (less noise)

```bash
./kredki-ui.sh --context-mode file
```

One finding per file, regardless of the number of matches.

---

### 🧾 Redacted report (safe to share)

```bash
./kredki-ui.sh --html --redact --context-mode file
```

Perfect for:
- sharing with third parties
- audit submissions
- external security teams

---

### 🤖 Non-interactive / CI mode

```bash
./kredki-ui.sh --non-interactive --html --context-mode file
```

No prompts, CI/CD ready.

---

### 📂 Custom paths and limits

```bash
./kredki-ui.sh \
  --paths /etc,/var,/srv \
  --max-filesize 5M \
  --html
```

---

### 🚫 Ignore files and directories

```bash
./kredki-ui.sh --ignore-file /root/.kredkiignore
```

---

## 📄 Reports

Generated artifacts:

- `kredki_found_<HOST>_<TIMESTAMP>.txt`
- `kredki_found_<HOST>_<TIMESTAMP>.html`
- `*.redacted.txt`

Terminal preview:
```bash
less -R kredki_found_*.txt
w3m kredki_found_*.html
```

---

## 🔐 Report Security

Reports may contain sensitive data.

Recommended permissions:
```bash
chmod 600 kredki_found_*
```

---

## 🧭 What KREDKI is NOT

- ❌ a pentest framework
- ❌ a privilege escalation tool
- ❌ a network scanner
- ❌ a SaaS product
- ❌ a telemetry system

---

## 📜 License

MIT License — use responsibly.

---

## 🧩 Project Philosophy

> *“Security findings without context are just noise.”*

KREDKI focuses on **meaningful risk**, not raw matches.
