# 🎨 KREDKI
## Fast Secret Scanner for Linux (Context-Aware)

**KREDKI** is an open‑source, context‑aware secret scanner for Linux systems.  
It detects **passwords, API tokens, private keys and credentials** stored in files.

Instead of exploitation, KREDKI focuses on **security context**.

> ⚠️ Scan only systems you own or are authorized to audit.

---

## 🚀 Why KREDKI?

Most scanners answer **“does a secret exist?”**  
KREDKI answers **“how risky is it?”**

---

## ✨ Features

- 🔍 Recursive filesystem scanning
- ⚡ High-performance search (ripgrep)
- 🧭 **Security Context**: HIGH / MEDIUM / LOW
- 📂 Per-directory statistics
- 🧩 Environment profiles
- 🛡️ Safe Production Mode
- 🧾 Redaction for safe sharing
- 📄 Security-ready HTML reports
- 🖥️ Clean CLI UI

---

## 🧠 Security Context

| Level | Meaning |
|----|----|
| 🔴 HIGH | Critical system secrets |
| 🟠 MEDIUM | Application secrets |
| 🟡 LOW | Temporary data |

---

## 📸 Screenshots

- CLI UI → [screenshots/ui.png](screenshots/ui.png)
- Summary → [screenshots/summary.png](screenshots/summary.png)
- HTML Report → [screenshots/html_report.png](screenshots/html_report.png)

---

## 📦 Requirements

```bash
sudo apt install -y ripgrep
```

---

## ▶️ Usage Examples

```bash
./kredki-ui.sh
./kredki-ui.sh --html
./kredki-ui.sh --context-mode file
./kredki-ui.sh --profile prod --safe
```

---

## 📜 License

MIT License
