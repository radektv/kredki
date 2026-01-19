# 🎨 KREDKI
### Fast Secret Scanner for Linux

**KREDKI** is a fast and security-focused tool for discovering
**secrets, passwords, tokens and keys** on Linux systems.

Instead of exploits, KREDKI focuses on **security context** —
where secrets are located and how risky they are.

> ⚠️ Scan only systems you own or have permission to audit.

---

## ✨ Features

- 🔍 Recursive filesystem scanning
- ⚡ High-performance search (ripgrep)
- 🧭 Security Context: HIGH / MEDIUM / LOW
- 📂 Per-directory statistics
- 🧾 Redaction for safe sharing
- 📄 Security-ready HTML reports
- 🧩 Environment profiles
- 🛡️ Safe Production Mode

---

## 📦 Requirements

- Linux
- bash >= 4.x
- ripgrep

```bash
sudo apt install -y ripgrep
```

---

## ▶️ Examples

```bash
./kredki-ui.sh --html --context-mode file
./kredki-ui.sh --profile prod --safe
```

---

## 📜 License
MIT
