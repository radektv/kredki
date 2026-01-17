#!/bin/bash
# ============================================================
#  K R E D K I  – Fast Secret Scanner for Linux
#  UI Wrapper (PRO+)
#  Version : 1.0-prostats
#
#  Adds:
#   - per-directory scan time
#   - per-directory hit counts
#   - total time + total hits
# ============================================================

set -euo pipefail

# ================== UI CONFIG ==================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SPINNER='|/-\'
# ===============================================

VERSION="1.0-prostats"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERN_FILE="$SCRIPT_DIR/patterns.txt"

# Must match scan paths used by kredki.sh
SCAN_PATHS=(
  /etc
  /home
  /root
  /opt
  /srv
  /var
)

# Same excludes as kredki.sh
EXCLUDES=(
  --glob '!.git/*'
  --glob '!node_modules/*'
  --glob '!vendor/*'
  --glob '!*.log'
  --glob '!*.bin'
  --glob '!*.zip'
)

# ================== FUNCTIONS ==================

banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  cat << EOF

██   ██    ██████    ███████    ██████    ██   ██    ██
██  ██     ██   ██   ██         ██   ██   ██  ██     ██
█████      ██████    █████      ██   ██   █████      ██
██  ██     ██   ██   ██         ██   ██   ██  ██     ██
██   ██    ██   ██   ███████    ██████    ██   ██    ██


              K   R   E   D   K   I
        🔍 Fast Secret Scanner for Linux
              Version ${VERSION}

EOF
  echo -e "${NC}"
}

check_deps() {
  for bin in rg; do
    if ! command -v "$bin" &>/dev/null; then
      echo -e "${RED}[✘] Missing dependency: $bin${NC}"
      echo -e "${YELLOW}Install on Debian/Ubuntu:${NC} sudo apt install -y ripgrep"
      exit 1
    fi
  done
}

check_patterns() {
  if [[ ! -f "$PATTERN_FILE" ]]; then
    echo -e "${RED}[✘] Missing patterns file:${NC} $PATTERN_FILE"
    exit 1
  fi
}

format_duration() {
  local seconds="${1:-0}"
  local hh=$((seconds / 3600))
  local mm=$(((seconds % 3600) / 60))
  local ss=$((seconds % 60))
  if (( hh > 0 )); then
    printf "%02d:%02d:%02d" "$hh" "$mm" "$ss"
  else
    printf "%02d:%02d" "$mm" "$ss"
  fi
}

print_scan_paths() {
  echo -e "${BOLD}📁 Scan paths (configured):${NC}"
  for dir in "${SCAN_PATHS[@]}"; do
    echo -e "  • $dir"
  done
}

get_existing_scan_paths() {
  for dir in "${SCAN_PATHS[@]}"; do
    [[ -d "$dir" ]] && echo "$dir"
  done
}

spinner() {
  local pid=$1
  local i=0
  tput civis || true
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r${YELLOW}[%c] Scanning system for secrets...${NC}" "${SPINNER:$i:1}"
    sleep 0.1
  done
  tput cnorm || true
  printf "\r${GREEN}[✔] Scan completed successfully!          ${NC}\n"
}

# Run scan sequentially per directory to measure per-dir time precisely.
run_scan() {
  local out_file="$1"; shift
  local -a dirs=("$@")

  local cpu rg_threads
  cpu="$(nproc)"
  rg_threads="$cpu"

  # stats arrays (keyed by index)
  declare -ga DIR_NAMES=()
  declare -ga DIR_SECONDS=()
  declare -ga DIR_HITS=()

  : > "$out_file"
  chmod 600 "$out_file"

  {
    echo "[*] Start scan: $(date)"
    echo "[*] CPU: $cpu | rg threads: $rg_threads"
    echo "[*] Patterns: $PATTERN_FILE"
    echo
  } >> "$out_file"

  local total_start total_end total_s
  total_start=$(date +%s)

  for d in "${dirs[@]}"; do
    local start end dur hits
    start=$(date +%s)

    # Header per directory (kept as [*] so it won't be counted as a hit)
    {
      echo "[*] --- Scanning: $d ---"
      echo "[*] Start: $(date)"
    } >> "$out_file"

    # Perform scan. Ignore rg exit code 1 (no matches).
    # Exit codes: 0 matches found, 1 no matches, 2 error.
    if rg -i \
        --threads "$rg_threads" \
        --no-heading \
        --line-number \
        -f "$PATTERN_FILE" \
        "${EXCLUDES[@]}" \
        "$d" >> "$out_file"; then
      :
    else
      rc=$?
      if [[ $rc -ne 1 ]]; then
        echo "[!] rg error (exit $rc) while scanning $d" >> "$out_file"
      fi
    fi

    end=$(date +%s)
    dur=$((end - start))

    # Count hits for this directory from the output file (lines starting with "dir/..." or "dir:...")
    hits=$(grep -v '^\[' "$out_file" 2>/dev/null | awk -v p="$d" 'index($0, p"/")==1 || index($0, p":")==1 {c++} END{print c+0}')

    DIR_NAMES+=("$d")
    DIR_SECONDS+=("$dur")
    DIR_HITS+=("$hits")

    {
      echo "[*] End: $(date)"
      echo "[*] Duration: ${dur}s"
      echo "[*] Hits: $hits"
      echo
    } >> "$out_file"
  done

  total_end=$(date +%s)
  total_s=$((total_end - total_start))

  {
    echo "[+] Finished: $(date)"
    echo "[+] Total duration: ${total_s}s"
    echo "[+] Results saved in: $out_file"
  } >> "$out_file"
}

summary() {
  local file="$1"
  local total_s="$2"

  local total_hits
  total_hits=$(grep -v '^\[' "$file" 2>/dev/null | wc -l | tr -d ' ')

  echo
  echo -e "${BOLD}📊 Scan Summary${NC}"
  echo -e "────────────────────────────────────────"
  echo -e "🏷️  Version            : ${CYAN}${VERSION}${NC}"
  echo -e "📁 Result file         : ${CYAN}${file}${NC}"
  echo -e "⏱️  Total scan time     : ${YELLOW}$(format_duration "$total_s")${NC}"
  echo -e "🔐 Total findings       : ${YELLOW}${total_hits}${NC}"
  echo

  echo -e "${BOLD}📂 Scanned directories (time / hits):${NC}"
  if (( ${#DIR_NAMES[@]} == 0 )); then
    echo -e "  ${YELLOW}(none — no configured paths exist on this system)${NC}"
  else
    local i
    for i in "${!DIR_NAMES[@]}"; do
      local d="${DIR_NAMES[$i]}"
      local s="${DIR_SECONDS[$i]}"
      local h="${DIR_HITS[$i]}"
      printf "  • %b%s%b  —  %b%s%b  —  %b%s hits%b\n" \
        "$CYAN" "$d" "$NC" \
        "$YELLOW" "$(format_duration "$s")" "$NC" \
        "$YELLOW" "$h" "$NC"
    done
  fi

  echo
  if (( total_hits > 0 )); then
    echo -e "${RED}⚠️  Action required:${NC} Review findings immediately."
  else
    echo -e "${GREEN}✅ No secrets detected.${NC}"
  fi
}

# ================== MAIN ==================

banner
check_deps
check_patterns

mapfile -t EXISTING_DIRS < <(get_existing_scan_paths)

echo -e "${BOLD}Configuration:${NC}"
echo -e "🧠 CPU cores      : $(nproc)"
echo -e "📜 Regex patterns : patterns.txt"
echo -e "🏷️  Version        : ${VERSION}"
echo
print_scan_paths
echo
echo -e "${BOLD}📂 Directories that will be scanned (exists):${NC}"
if (( ${#EXISTING_DIRS[@]} == 0 )); then
  echo -e "  ${YELLOW}(none found)${NC}"
else
  for d in "${EXISTING_DIRS[@]}"; do
    echo -e "  • ${CYAN}${d}${NC}"
  done
fi

echo
echo -e "${YELLOW}⚠️  This scan may expose sensitive data.${NC}"
echo -e "👉 Run only on systems you own or have permission to scan."
echo
read -rp "Press ENTER to start scanning..."

OUT_FILE="$SCRIPT_DIR/kredki_found_$(date +%F_%H-%M-%S).txt"

echo
# Run scan in background to keep spinner UX
(
  run_scan "$OUT_FILE" "${EXISTING_DIRS[@]}"
) &
SCAN_PID=$!

spinner "$SCAN_PID"

# Read total duration from output file
TOTAL_S_LINE=$(grep -E '^\[\+\] Total duration:' "$OUT_FILE" 2>/dev/null | tail -n1 | awk '{print $4}' | tr -d 's' || true)
if [[ -n "${TOTAL_S_LINE:-}" ]]; then
  TOTAL_S="$TOTAL_S_LINE"
else
  TOTAL_S=0
fi

# Rebuild per-dir stats from output file (so they're available in this shell)
DIR_NAMES=()
DIR_SECONDS=()
DIR_HITS=()

while IFS= read -r line; do
  case "$line" in
    "[*] --- Scanning:"*)
      d="${line#'[*] --- Scanning: '}"
      d="${d%' ---'}"
      DIR_NAMES+=("$d")
      ;;
    "[*] Duration:"*)
      s="${line#'[*] Duration: '}"
      s="${s%s}"
      DIR_SECONDS+=("$s")
      ;;
    "[*] Hits:"*)
      h="${line#'[*] Hits: '}"
      DIR_HITS+=("$h")
      ;;
  esac
done < "$OUT_FILE"

summary "$OUT_FILE" "$TOTAL_S"

echo
echo -e "${BLUE}✨ Tip:${NC} Open the result file in a pager:"
echo -e "   less -R $OUT_FILE"
echo

