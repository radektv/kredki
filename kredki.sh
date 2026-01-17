#!/bin/bash
set -euo pipefail

# ===== ŚCIEŻKI =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERN_FILE="$SCRIPT_DIR/patterns.txt"

# ===== WALIDACJA =====
if [[ ! -f "$PATTERN_FILE" ]]; then
  echo "[!] BRAK pliku z regexami: $PATTERN_FILE" >&2
  exit 1
fi

# ===== SPRZĘT =====
CPU=$(nproc)
PARALLEL_JOBS=$CPU
RG_THREADS=$CPU

# ===== OUTPUT =====
OUT="$SCRIPT_DIR/kredki_found_$(date +%F_%H-%M-%S).txt"
touch "$OUT"
chmod 600 "$OUT"

# ===== KATALOGI (MOGĄ NIE ISTNIEĆ) =====
SEARCH_PATHS=(
  /etc
  /home
  /root
  /opt
  /srv
  /var
)

# ===== WYKLUCZENIA =====
EXCLUDES=(
  --glob '!.git/*'
  --glob '!node_modules/*'
  --glob '!vendor/*'
  --glob '!*.log'
  --glob '!*.bin'
  --glob '!*.zip'
)

echo "[*] Start skanowania: $(date)" | tee -a "$OUT"
echo "[*] CPU: $CPU | rg threads: $RG_THREADS | parallel jobs: $PARALLEL_JOBS" | tee -a "$OUT"

export RG_THREADS PATTERN_FILE OUT

# ===== FILTR KATALOGÓW + RÓWNOLEGŁOŚĆ =====
for d in "${SEARCH_PATHS[@]}"; do
  [[ -d "$d" ]] && echo "$d"
done | parallel -j "$PARALLEL_JOBS" '
  rg -i \
     --threads "$RG_THREADS" \
     --no-heading \
     --line-number \
     -f "$PATTERN_FILE" \
     '"${EXCLUDES[*]}"' \
     {} >> "$OUT"
'

echo "[+] Zakończono: $(date)" | tee -a "$OUT"
echo "[+] Wyniki zapisane w: $OUT"

