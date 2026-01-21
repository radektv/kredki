#!/bin/bash
# ============================================================
#  K R E D K I  – Fast Secret Scanner for Linux
#  UI Wrapper (PRO+HTML+REPORT)
#
#  v1.4.1-pro-html-meta-exclude-self
#   FIXES:
#    - Proper ripgrep argument handling (no broken quoting) ✅
#    - Clean, readable TXT report (separate from raw log) ✅
#
#  FEATURES:
#   - File metadata (chmod/chown style) in TXT + HTML (optional)
#   - Auto-exclude the KREDKI project directory from scans
#   - Auto-exclude kredki_found_*.txt/html and *.redacted.txt from scans
#   - Profiles, safe mode, context mode, HTML, redaction
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

VERSION="1.4.1-pro-html-meta-exclude-self"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERN_FILE="$SCRIPT_DIR/patterns.txt"
PROFILES_DIR="$SCRIPT_DIR/profiles"

# Defaults (overridable by profiles)
PROFILE_NAME="default"
SCAN_PATHS=(/etc /home /root /opt /srv /var)
MAX_FILE_SIZE="5M"
SAFE_MODE=false
FOLLOW_SYMLINKS=false

ENABLE_SECURITY_CONTEXT=true
ENABLE_HIGH_RISK=true
ENABLE_MEDIUM_RISK=true
ENABLE_LOW_RISK=true

NON_INTERACTIVE=false
NO_SPINNER=false

GENERATE_HTML=false
HTML_FILE=""

CONTEXT_MODE="line"        # line | file
REDACT=false               # for TXT output (optional)
REDACT_HTML_DEFAULT=true   # HTML is redacted by default

# Permissions / ownership metadata
INCLUDE_FILE_METADATA=true

# Exclusions (base)
EXCLUDE_PATHS=(/proc /sys /dev)
EXCLUDE_GLOBS=(
  --glob '!.git/*'
  --glob '!node_modules/*'
  --glob '!vendor/*'
)

# Auto-exclude project dir (this repo)
AUTO_EXCLUDE_PROJECT_DIR=true
PROJECT_DIR="$SCRIPT_DIR"

# ================== HELPERS ==================

usage() {
  cat << 'EOF'
KREDKI UI (PRO+HTML+REPORT)

Options:
  --profile <name>          Load profile from profiles/<name>.conf (default: default)
  --safe                    Enable Safe Production Mode
  --paths <csv>             Override scan paths, e.g. /etc,/home,/var
  --max-filesize <size>     Override max file size for rg (e.g. 2M, 10M)
  --follow-symlinks         Follow symlinks (rg --follow)
  --no-spinner              Disable spinner
  --non-interactive         Do not prompt "Press ENTER" (useful for CI)

  --context-mode <mode>     line (default) or file (unique files per context)
  --redact                  Redact secrets in TXT + HTML reports
  --no-redact               Disable redaction (HTML + TXT)

  --html                    Generate HTML report next to TXT
  --html-file <path>        Custom HTML report path

  --file-metadata           Include chmod/chown-style metadata in TXT+HTML (default)
  --no-file-metadata        Disable file metadata sections

  -h, --help                Show this help

Examples:
  ./kredki-ui.sh --paths /etc,/home --html
  ./kredki-ui.sh --profile prod --safe --html --context-mode file
  ./kredki-ui.sh --html --redact --context-mode file
EOF
}

die() { echo -e "${RED}[✘]${NC} $*" >&2; exit 1; }

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

banner() {
  clear || true
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

spinner() {
  local pid=$1
  local i=0
  [[ "$NO_SPINNER" == "true" ]] && return 0
  tput civis || true
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r${YELLOW}[%c] Scanning system for secrets...${NC}" "${SPINNER:$i:1}"
    sleep 0.1
  done
  tput cnorm || true
  printf "\r${GREEN}[✔] Scan completed successfully!          ${NC}\n"
}

check_deps() {
  command -v rg >/dev/null 2>&1 || die "Missing dependency: rg (ripgrep). Install: sudo apt install -y ripgrep"
  command -v awk >/dev/null 2>&1 || die "Missing dependency: awk"
  command -v sed >/dev/null 2>&1 || die "Missing dependency: sed"
  command -v stat >/dev/null 2>&1 || die "Missing dependency: stat (coreutils)"
}

check_patterns() { [[ -f "$PATTERN_FILE" ]] || die "Missing patterns file: $PATTERN_FILE"; }

csv_to_array() { local csv="$1"; local IFS=','; read -r -a _arr <<< "$csv"; printf '%s\n' "${_arr[@]}"; }

load_profile() {
  local name="$1"
  local file="$PROFILES_DIR/$name.conf"

  if [[ ! -d "$PROFILES_DIR" ]]; then
    [[ "$name" == "default" ]] || die "Profiles directory not found: $PROFILES_DIR (requested profile: $name)"
    return 0
  fi
  if [[ ! -f "$file" ]]; then
    [[ "$name" == "default" ]] || die "Profile not found: $file"
    return 0
  fi

  # shellcheck disable=SC1090
  source "$file"
  PROFILE_NAME="${PROFILE_NAME:-$name}"
}

apply_safe_mode() {
  [[ "$SAFE_MODE" == "true" ]] || return 0
  MAX_FILE_SIZE="${MAX_FILE_SIZE:-2M}"
  FOLLOW_SYMLINKS=false
  ENABLE_LOW_RISK=false
  EXCLUDE_PATHS+=(/tmp /var/tmp)
  for p in "${SCAN_PATHS[@]}"; do
    [[ "$p" == "/" ]] && die "SAFE_MODE=true forbids scanning '/' (too risky). Use narrower paths."
  done
}

get_existing_scan_paths() { for p in "${SCAN_PATHS[@]}"; do [[ -d "$p" ]] && echo "$p"; done; }

print_config() {
  echo -e "${BOLD}Configuration:${NC}"
  echo -e "🏷️  Profile            : ${CYAN}${PROFILE_NAME}${NC}"
  echo -e "🧠 CPU cores          : $(nproc)"
  echo -e "📜 Patterns           : $(basename "$PATTERN_FILE")"
  echo -e "📦 Max file size      : ${MAX_FILE_SIZE}"
  echo -e "🛡️  Safe mode          : ${SAFE_MODE}"
  echo -e "🔗 Follow symlinks    : ${FOLLOW_SYMLINKS}"
  echo -e "🧭 Security context   : ${ENABLE_SECURITY_CONTEXT} (mode: ${CONTEXT_MODE})"
  echo -e "🧾 HTML report         : ${GENERATE_HTML}"
  echo -e "🧽 Redaction           : TXT=${REDACT} | HTML=${HTML_REDACT}"
  echo -e "🔐 File metadata       : ${INCLUDE_FILE_METADATA}"
  echo
  echo -e "${BOLD}📁 Scan paths (configured):${NC}"
  for p in "${SCAN_PATHS[@]}"; do echo -e "  • $p"; done
  echo
  echo -e "${BOLD}🚫 Excluded paths:${NC}"
  for p in "${EXCLUDE_PATHS[@]}"; do echo -e "  • $p"; done
  echo
  if [[ "$AUTO_EXCLUDE_PROJECT_DIR" == "true" ]]; then
    echo -e "${BOLD}🧯 Auto-exclude:${NC}"
    echo -e "  • Project dir: ${CYAN}${PROJECT_DIR}${NC}"
    echo -e "  • Output files: kredki_found_*.txt / *.html / *.redacted.txt"
    echo
  fi
}

# -------- Security context by file location --------
ctx_for_path() {
  local f="$1"
  if [[ "$f" == /etc/* || "$f" == /root/* || "$f" == /opt/* ]]; then echo "HIGH"; return; fi
  if [[ "$f" == */.env || "$f" == */.env.* || "$f" == */.git-credentials || "$f" == */.npmrc || "$f" == */.pypirc ]]; then echo "HIGH"; return; fi
  if [[ "$f" == /tmp/* || "$f" == /var/tmp/* || "$f" == /dev/shm/* ]]; then echo "LOW"; return; fi
  echo "MEDIUM"
}

# -------- Redaction (best-effort) --------
redact_line() {
  local line="$1"
  local file="${line%%:*}"
  local rest="${line#*:}"
  local lineno="${rest%%:*}"
  local content="${rest#*:}"
  local redacted
  redacted="$(printf '%s' "$content" | sed -E \
    -e 's/((password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)[[:space:]]*[:=][[:space:]]*)(["'\''`]?)[^"'\''` ,;)]*/\1\3<REDACTED>/Ig' \
    -e 's/(\b(authorization|bearer)[[:space:]]+)[A-Za-z0-9._-]+/\1<REDACTED>/Ig' \
    -e 's/([A-Z0-9_]{6,}_(TOKEN|SECRET|PASSWORD|KEY)[A-Z0-9_]*[[:space:]]*[:=][[:space:]]*)(["'\''`]?)[^"'\''` ,;)]*/\1\3<REDACTED>/g' \
  )"
  printf '%s:%s:%s\n' "$file" "$lineno" "$redacted"
}

# -------- File metadata cache --------
declare -A META_CACHE=()

file_meta() {
  local f="$1"
  [[ "$INCLUDE_FILE_METADATA" != "true" ]] && return 0

  if [[ -n "${META_CACHE[$f]+x}" ]]; then
    printf '%s' "${META_CACHE[$f]}"
    return 0
  fi

  if [[ ! -e "$f" ]]; then
    META_CACHE["$f"]="[missing]"
    printf '%s' "${META_CACHE[$f]}"
    return 0
  fi

  local perm_sym perm_oct owner group
  perm_sym="$(stat -c '%A' "$f" 2>/dev/null || echo '?')"
  perm_oct="$(stat -c '%a' "$f" 2>/dev/null || echo '?')"
  owner="$(stat -c '%U' "$f" 2>/dev/null || echo '?')"
  group="$(stat -c '%G' "$f" 2>/dev/null || echo '?')"

  META_CACHE["$f"]="perm=${perm_sym} (${perm_oct}) owner=${owner}:${group} | chmod ${perm_oct} \"$f\" | chown ${owner}:${group} \"$f\""
  printf '%s' "${META_CACHE[$f]}"
}

# Build ripgrep args array for a scan root (FIXED: no broken quoting)
RG_ARGS=()
rg_args_for_root() {
  local root="$1"
  local cpu="$2"
  RG_ARGS=(
    -i --threads "$cpu" --no-heading --line-number
    --max-filesize "$MAX_FILE_SIZE"
    -f "$PATTERN_FILE"
    --glob '!kredki_found_*.txt'
    --glob '!kredki_found_*.html'
    --glob '!*\.redacted\.txt'
  )

  [[ "$FOLLOW_SYMLINKS" == "true" ]] && RG_ARGS+=(--follow) || RG_ARGS+=(--no-follow)
  RG_ARGS+=("${EXCLUDE_GLOBS[@]}")

  if [[ "$AUTO_EXCLUDE_PROJECT_DIR" == "true" ]]; then
    case "$PROJECT_DIR" in
      "$root"|"$root"/*)
        local rel="${PROJECT_DIR#"$root"/}"
        if [[ "$rel" != "$PROJECT_DIR" && -n "$rel" ]]; then
          RG_ARGS+=(--glob "!${rel}/**")
        elif [[ "$PROJECT_DIR" == "$root" ]]; then
          RG_ARGS+=(--glob "!**")
        fi
        ;;
    esac
  fi
}

# RAW scan -> only matches (no debug markers) for clean parsing
run_scan_raw() {
  local raw_file="$1"; shift
  local -a dirs=("$@")
  local cpu; cpu="$(nproc)"

  : > "$raw_file"
  chmod 600 "$raw_file"

  local total_start total_end total_s
  total_start=$(date +%s)

  local d
  for d in "${dirs[@]}"; do
    local ex skip=false
    for ex in "${EXCLUDE_PATHS[@]}"; do
      if [[ "$d" == "$ex" || "$d" == "$ex/"* ]]; then skip=true; break; fi
    done
    [[ "$skip" == "true" ]] && continue

    rg_args_for_root "$d" "$cpu"
    # shellcheck disable=SC2317
    if rg "${RG_ARGS[@]}" "$d" >> "$raw_file"; then
      :
    else
      rc=$?
      # rg exit 1 = no matches; anything else is an error
      [[ $rc -ne 1 ]] && printf '[!] rg error (exit %s) while scanning %s\n' "$rc" "$d" >> "$raw_file"
    fi
  done

  total_end=$(date +%s)
  total_s=$((total_end - total_start))
  echo "$total_s"
}

# -------- Stats / report building --------
DIR_NAMES=(); DIR_SECONDS=(); DIR_HITS=()
CTX_HIGH=0; CTX_MEDIUM=0; CTX_LOW=0
BREAK_HIGH=(); BREAK_MEDIUM=(); BREAK_LOW=()
declare -A SEEN_HIGH=(); declare -A SEEN_MEDIUM=(); declare -A SEEN_LOW=()
declare -A UNIQUE_FILES=()
declare -A FILE_HITS=()

total_hits_from_file() { wc -l < "$1" | tr -d ' '; }

print_context_rules() {
  cat << 'EOF'
Zasady (wnioskowanie po ścieżce, nie sygnał exploita):
  HIGH   → /etc, /root, /opt  +  *.env, .git-credentials, .npmrc, .pypirc
  MEDIUM → domyślnie reszta (np. /var, /home, /srv)
  LOW    → /tmp, /var/tmp, /dev/shm
EOF
}

parse_from_raw() {
  local raw_file="$1"

  CTX_HIGH=0; CTX_MEDIUM=0; CTX_LOW=0
  BREAK_HIGH=(); BREAK_MEDIUM=(); BREAK_LOW=()
  SEEN_HIGH=(); SEEN_MEDIUM=(); SEEN_LOW=()
  UNIQUE_FILES=(); FILE_HITS=()

  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    [[ "$m" == \[* ]] && continue  # skip rg error lines
    local file="${m%%:*}"
    UNIQUE_FILES["$file"]=1
    FILE_HITS["$file"]=$(( ${FILE_HITS["$file"]:-0} + 1 ))

    [[ "$ENABLE_SECURITY_CONTEXT" == "true" ]] || continue
    local ctx; ctx="$(ctx_for_path "$file")"

    if [[ "$CONTEXT_MODE" == "file" ]]; then
      case "$ctx" in
        HIGH)   if [[ -z "${SEEN_HIGH[$file]+x}" ]]; then SEEN_HIGH["$file"]=1; BREAK_HIGH+=("$file"); [[ "$ENABLE_HIGH_RISK" == "true" ]] && ((++CTX_HIGH)); fi ;;
        MEDIUM) if [[ -z "${SEEN_MEDIUM[$file]+x}" ]]; then SEEN_MEDIUM["$file"]=1; BREAK_MEDIUM+=("$file"); [[ "$ENABLE_MEDIUM_RISK" == "true" ]] && ((++CTX_MEDIUM)); fi ;;
        LOW)    if [[ -z "${SEEN_LOW[$file]+x}" ]]; then SEEN_LOW["$file"]=1; BREAK_LOW+=("$file"); [[ "$ENABLE_LOW_RISK" == "true" ]] && ((++CTX_LOW)); fi ;;
      esac
    else
      case "$ctx" in
        HIGH)   BREAK_HIGH+=("$m"); [[ "$ENABLE_HIGH_RISK" == "true" ]] && ((++CTX_HIGH)) ;;
        MEDIUM) BREAK_MEDIUM+=("$m"); [[ "$ENABLE_MEDIUM_RISK" == "true" ]] && ((++CTX_MEDIUM)) ;;
        LOW)    BREAK_LOW+=("$m"); [[ "$ENABLE_LOW_RISK" == "true" ]] && ((++CTX_LOW)) ;;
      esac
    fi
  done < "$raw_file"
}

# Per-directory stats (time + hits)
scan_dirs_with_stats() {
  local raw_file="$1"; shift
  local -a dirs=("$@")
  local cpu; cpu="$(nproc)"

  DIR_NAMES=(); DIR_SECONDS=(); DIR_HITS=()

  local d
  for d in "${dirs[@]}"; do
    local ex skip=false
    for ex in "${EXCLUDE_PATHS[@]}"; do
      if [[ "$d" == "$ex" || "$d" == "$ex/"* ]]; then skip=true; break; fi
    done
    [[ "$skip" == "true" ]] && continue

    local start end dur hits
    start=$(date +%s)
    local tmp; tmp="$(mktemp)"

    rg_args_for_root "$d" "$cpu"
    if rg "${RG_ARGS[@]}" "$d" > "$tmp"; then :; else
      rc=$?
      [[ $rc -ne 1 ]] && printf '[!] rg error (exit %s) while scanning %s\n' "$rc" "$d" >> "$raw_file"
    fi

    cat "$tmp" >> "$raw_file"
    end=$(date +%s)
    dur=$((end - start))
    hits=$(wc -l < "$tmp" | tr -d ' ')

    DIR_NAMES+=("$d")
    DIR_SECONDS+=("$dur")
    DIR_HITS+=("$hits")

    rm -f "$tmp"
  done
}

write_report_txt() {
  local raw_file="$1"
  local report_file="$2"
  local total_s="$3"

  local total_hits; total_hits="$(total_hits_from_file "$raw_file")"

  : > "$report_file"
  chmod 600 "$report_file"

  {
    echo "KREDKI Report"
    echo "Version: $VERSION"
    echo "Generated: $(date)"
    echo "Profile: $PROFILE_NAME"
    echo "Scan paths: ${SCAN_PATHS[*]}"
    echo "Excluded paths: ${EXCLUDE_PATHS[*]}"
    echo "Auto-exclude project dir: $AUTO_EXCLUDE_PROJECT_DIR ($PROJECT_DIR)"
    echo "Context mode: $CONTEXT_MODE"
    echo "Redaction: TXT=$REDACT | HTML=$HTML_REDACT"
    echo "File metadata: $INCLUDE_FILE_METADATA"
    echo
    echo "Summary"
    echo "------"
    echo "Total scan time: $(format_duration "$total_s")"
    echo "Total findings: $total_hits"
    echo
    echo "Directories (time / hits)"
    echo "------------------------"
    if (( ${#DIR_NAMES[@]} == 0 )); then
      echo "(none)"
    else
      for i in "${!DIR_NAMES[@]}"; do
        printf "%-30s  %8s  %6s hits\n" "${DIR_NAMES[$i]}" "$(format_duration "${DIR_SECONDS[$i]}")" "${DIR_HITS[$i]}"
      done
    fi

    if [[ "$ENABLE_SECURITY_CONTEXT" == "true" ]]; then
      echo
      echo "Security Context"
      echo "----------------"
      printf "HIGH:   %s\n" "$CTX_HIGH"
      printf "MEDIUM: %s\n" "$CTX_MEDIUM"
      printf "LOW:    %s\n" "$CTX_LOW"
      echo
      print_context_rules
    fi

    if (( total_hits > 0 )); then
      echo
      echo "Files (unique) + access/ownership"
      echo "--------------------------------"
      if [[ "$INCLUDE_FILE_METADATA" == "true" ]]; then
        for f in "${!UNIQUE_FILES[@]}"; do
          echo "$f"
          echo "  $(file_meta "$f")"
          echo "  hits: ${FILE_HITS["$f"]:-0}"
          echo
        done
      else
        for f in "${!UNIQUE_FILES[@]}"; do
          echo "$f (hits: ${FILE_HITS["$f"]:-0})"
        done
      fi

      echo
      echo "Findings (raw matches)"
      echo "---------------------"
      if [[ "$REDACT" == "true" ]]; then
        while IFS= read -r l; do
          [[ -z "$l" ]] && continue
          [[ "$l" == \[* ]] && continue
          redact_line "$l"
        done < "$raw_file"
      else
        cat "$raw_file"
      fi
    else
      echo
      echo "No findings."
    fi
  } >> "$report_file"
}

# -------- HTML helpers --------
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

html_list_items() { while IFS= read -r line; do [[ -z "$line" ]] && continue; printf '<li><code>%s</code></li>\n' "$(printf '%s' "$line" | html_escape)"; done; }

html_meta_rows() {
  [[ "$INCLUDE_FILE_METADATA" == "true" ]] || return 0
  local count=0 max_show=400
  for f in "${!UNIQUE_FILES[@]}"; do
    ((count++)); [[ $count -gt $max_show ]] && break
    local meta; meta="$(file_meta "$f")"
    printf '<tr><td><code>%s</code></td><td><code>%s</code></td><td>%s</td></tr>\n' \
      "$(printf '%s' "$f" | html_escape)" \
      "$(printf '%s' "$meta" | html_escape)" \
      "${FILE_HITS["$f"]:-0}"
  done
}

generate_html_report() {
  local raw_file="$1" total_s="$2" html_out="$3"
  local total_hits; total_hits="$(total_hits_from_file "$raw_file")"

  local dir_rows=""
  if (( ${#DIR_NAMES[@]} > 0 )); then
    for i in "${!DIR_NAMES[@]}"; do
      dir_rows+=$'<tr><td><code>'"$(printf '%s' "${DIR_NAMES[$i]}" | html_escape)"$'</code></td><td>'"$(format_duration "${DIR_SECONDS[$i]}")"$'</td><td>'"${DIR_HITS[$i]}"$'</td></tr>\n'
    done
  fi

  local high_list medium_list low_list
  high_list="$(printf '%s\n' "${BREAK_HIGH[@]:-}" | html_list_items || true)"
  medium_list="$(printf '%s\n' "${BREAK_MEDIUM[@]:-}" | html_list_items || true)"
  low_list="$(printf '%s\n' "${BREAK_LOW[@]:-}" | html_list_items || true)"

  local findings_raw
  if [[ "$HTML_REDACT" == "true" ]]; then
    findings_raw="$(while IFS= read -r l; do [[ -z "$l" ]] && continue; [[ "$l" == \[* ]] && continue; redact_line "$l"; done < "$raw_file" | html_escape || true)"
  else
    findings_raw="$(cat "$raw_file" | html_escape || true)"
  fi

  local rules_html; rules_html="$(print_context_rules | html_escape | sed 's/$/<br>/' )"
  local meta_rows=""
  if [[ "$INCLUDE_FILE_METADATA" == "true" && $total_hits -gt 0 ]]; then
    meta_rows="$(html_meta_rows)"
  fi

  cat > "$html_out" <<EOF
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>KREDKI Report</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,Arial,sans-serif;margin:24px;line-height:1.35}
.wrap{max-width:1120px;margin:0 auto}
.muted{color:#666}
.card{border:1px solid #ddd;border-radius:14px;padding:16px;margin:16px 0}
.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}
@media (max-width:900px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:520px){.grid{grid-template-columns:1fr}}
.pill{display:flex;gap:8px;align-items:center;padding:10px 12px;border-radius:999px;border:1px solid #e6e6e6;background:#fafafa}
table{border-collapse:collapse;width:100%} th,td{border-bottom:1px solid #eee;text-align:left;padding:10px;vertical-align:top} th{background:#fafafa}
code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
pre{background:#0b0f14;color:#e6edf3;border-radius:14px;padding:14px;overflow:auto;white-space:pre-wrap;word-break:break-word}
.high{color:#b00020;font-weight:800}.med{color:#b26a00;font-weight:800}.low{color:#0b6e4f;font-weight:800}
.btns{display:flex;gap:10px;flex-wrap:wrap;margin-top:10px} button{border:1px solid #ddd;background:#fff;border-radius:10px;padding:8px 10px;cursor:pointer}
button:hover{background:#f7f7f7}
details{border:1px solid #eee;border-radius:14px;padding:12px;margin:10px 0;background:#fff} summary{cursor:pointer;font-weight:700}
ul{margin:10px 0 0 18px}
.warn{color:#7a4b00}
</style></head><body><div class="wrap">
<h1>🎨 KREDKI Report</h1>
<div class="muted">Generated: $(date) • Version: ${VERSION} • Profile: ${PROFILE_NAME}</div>

<div class="card">
  <div class="grid">
    <div class="pill">⏱️ <span>Total time</span> <b>$(format_duration "$total_s")</b></div>
    <div class="pill">🔐 <span>Findings</span> <b>${total_hits}</b></div>
    <div class="pill">🛡️ <span>Safe mode</span> <b>${SAFE_MODE}</b></div>
    <div class="pill">📦 <span>Max file size</span> <b>${MAX_FILE_SIZE}</b></div>
  </div>
  <div class="btns">
    <button onclick="filterCtx('ALL')">Show all</button>
    <button onclick="filterCtx('HIGH')">HIGH only</button>
    <button onclick="filterCtx('MEDIUM')">MEDIUM only</button>
    <button onclick="filterCtx('LOW')">LOW only</button>
  </div>
  <div class="muted" style="margin-top:10px">
    Context mode: <b>${CONTEXT_MODE}</b> • HTML redaction: <b>${HTML_REDACT}</b> • File metadata: <b>${INCLUDE_FILE_METADATA}</b>
  </div>
</div>

<div class="card"><h2>📂 Directories (time / hits)</h2>
<table><thead><tr><th>Directory</th><th>Time</th><th>Hits</th></tr></thead><tbody>
${dir_rows:-<tr><td colspan="3" class="muted">No directory stats available.</td></tr>}
</tbody></table></div>

<div class="card"><h2>🧭 Security Context</h2>
<div class="muted" style="margin-bottom:10px">${rules_html}</div>
<table><thead><tr><th>Level</th><th>Count</th></tr></thead><tbody>
<tr class="ctx HIGH"><td class="high">HIGH</td><td>${CTX_HIGH}</td></tr>
<tr class="ctx MEDIUM"><td class="med">MEDIUM</td><td>${CTX_MEDIUM}</td></tr>
<tr class="ctx LOW"><td class="low">LOW</td><td>${CTX_LOW}</td></tr>
</tbody></table>

<details class="ctx HIGH"><summary><span class="high">HIGH</span> breakdown</summary><ul>${high_list:-<li class="muted">none</li>}</ul></details>
<details class="ctx MEDIUM"><summary><span class="med">MEDIUM</span> breakdown</summary><ul>${medium_list:-<li class="muted">none</li>}</ul></details>
<details class="ctx LOW"><summary><span class="low">LOW</span> breakdown</summary><ul>${low_list:-<li class="muted">none</li>}</ul></details>
</div>

<div class="card"><h2>🔐 File Access & Ownership</h2>
<div class="muted">Shows current permissions and ownership for files that produced findings. The chmod/chown commands reproduce current state.</div>
<table><thead><tr><th>File</th><th>Metadata (chmod / chown)</th><th>Hits</th></tr></thead><tbody>
${meta_rows:-<tr><td colspan="3" class="muted">File metadata disabled or no findings.</td></tr>}
</tbody></table></div>

<div class="card"><h2>🔎 Findings (raw matches)</h2>
<div class="muted">Tip: share the HTML report with redaction enabled.</div>
<pre>${findings_raw}</pre></div>

<div class="muted warn">⚠️ This report may contain sensitive data. Share carefully.</div>
</div>
<script>
function filterCtx(level){
  const nodes = document.querySelectorAll('.ctx');
  nodes.forEach(n=>{
    if(level==='ALL'){ n.style.display=''; return; }
    n.style.display = n.classList.contains(level) ? '' : 'none';
  });
}
</script>
</body></html>
EOF
}

# ================== ARG PARSER ==================

PROFILE_REQUESTED="default"
OVERRIDE_PATHS_CSV=""
OVERRIDE_MAX_FILESIZE=""
OVERRIDE_FOLLOW_SYMLINKS=false
OVERRIDE_CONTEXT_MODE=""
OVERRIDE_REDACT=""
OVERRIDE_NO_REDACT=false
OVERRIDE_GENERATE_HTML=false
OVERRIDE_HTML_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || die "--profile requires a value"; PROFILE_REQUESTED="$2"; shift 2 ;;
    --safe) SAFE_MODE=true; shift ;;
    --paths) [[ $# -ge 2 ]] || die "--paths requires a csv list"; OVERRIDE_PATHS_CSV="$2"; shift 2 ;;
    --max-filesize) [[ $# -ge 2 ]] || die "--max-filesize requires a value"; OVERRIDE_MAX_FILESIZE="$2"; shift 2 ;;
    --follow-symlinks) OVERRIDE_FOLLOW_SYMLINKS=true; shift ;;
    --no-spinner) NO_SPINNER=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --context-mode) [[ $# -ge 2 ]] || die "--context-mode requires: line|file"; OVERRIDE_CONTEXT_MODE="$2"; shift 2 ;;
    --redact) OVERRIDE_REDACT="true"; shift ;;
    --no-redact) OVERRIDE_NO_REDACT=true; shift ;;
    --html) OVERRIDE_GENERATE_HTML=true; shift ;;
    --html-file) [[ $# -ge 2 ]] || die "--html-file requires a value"; OVERRIDE_HTML_FILE="$2"; shift 2 ;;
    --file-metadata) INCLUDE_FILE_METADATA=true; shift ;;
    --no-file-metadata) INCLUDE_FILE_METADATA=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

# ================== MAIN ==================

banner
check_deps
check_patterns
load_profile "$PROFILE_REQUESTED"

# Apply overrides after profile
[[ -n "$OVERRIDE_PATHS_CSV" ]] && mapfile -t SCAN_PATHS < <(csv_to_array "$OVERRIDE_PATHS_CSV")
[[ -n "$OVERRIDE_MAX_FILESIZE" ]] && MAX_FILE_SIZE="$OVERRIDE_MAX_FILESIZE"
[[ "$OVERRIDE_FOLLOW_SYMLINKS" == "true" ]] && FOLLOW_SYMLINKS=true
[[ -n "$OVERRIDE_CONTEXT_MODE" ]] && CONTEXT_MODE="$OVERRIDE_CONTEXT_MODE"
[[ "$OVERRIDE_GENERATE_HTML" == "true" ]] && GENERATE_HTML=true
[[ -n "$OVERRIDE_HTML_FILE" ]] && HTML_FILE="$OVERRIDE_HTML_FILE"

[[ "$CONTEXT_MODE" != "line" && "$CONTEXT_MODE" != "file" ]] && die "--context-mode must be: line or file"

# Redaction logic
if [[ "$OVERRIDE_NO_REDACT" == "true" ]]; then
  REDACT=false
  HTML_REDACT=false
else
  REDACT="${OVERRIDE_REDACT:-false}"
  HTML_REDACT="$REDACT_HTML_DEFAULT"
fi
[[ "$REDACT" == "true" ]] && HTML_REDACT=true

apply_safe_mode

mapfile -t EXISTING_DIRS < <(get_existing_scan_paths)
print_config

echo -e "${BOLD}📂 Directories that will be scanned (exists):${NC}"
if (( ${#EXISTING_DIRS[@]} == 0 )); then
  echo -e "  ${YELLOW}(none found)${NC}"
else
  for d in "${EXISTING_DIRS[@]}"; do echo -e "  • ${CYAN}${d}${NC}"; done
fi

echo
echo -e "${YELLOW}⚠️  This scan may expose sensitive data.${NC}"
echo -e "👉 Run only on systems you own or have permission to scan."
echo

if [[ "$NON_INTERACTIVE" != "true" ]]; then
  read -rp "Press ENTER to start scanning..."
fi

TS="$(date +%F_%H-%M-%S)"
RAW_FILE="$SCRIPT_DIR/kredki_found_${TS}.raw.txt"
REPORT_FILE="$SCRIPT_DIR/kredki_found_${TS}.txt"

echo
: > "$RAW_FILE"
chmod 600 "$RAW_FILE"

TOTAL_START=$(date +%s)
scan_dirs_with_stats "$RAW_FILE" "${EXISTING_DIRS[@]}"
TOTAL_END=$(date +%s)
TOTAL_S=$((TOTAL_END - TOTAL_START))

parse_from_raw "$RAW_FILE"
write_report_txt "$RAW_FILE" "$REPORT_FILE" "$TOTAL_S"

# Show success
echo -e "${GREEN}[✔] Scan completed successfully!${NC}"
echo
echo -e "${BOLD}📊 Scan Summary${NC}"
echo -e "────────────────────────────────────────"
echo -e "📁 Report TXT : ${CYAN}${REPORT_FILE}${NC}"
echo -e "📁 Raw matches: ${CYAN}${RAW_FILE}${NC}"
echo -e "⏱️  Total time : ${YELLOW}$(format_duration "$TOTAL_S")${NC}"
echo -e "🔐 Findings   : ${YELLOW}$(total_hits_from_file "$RAW_FILE")${NC}"

# Optional HTML
if [[ "$GENERATE_HTML" == "true" ]]; then
  [[ -z "$HTML_FILE" ]] && HTML_FILE="${REPORT_FILE%.txt}.html"
  generate_html_report "$RAW_FILE" "$TOTAL_S" "$HTML_FILE"
  echo -e "📄 HTML       : ${CYAN}${HTML_FILE}${NC}"
fi

echo
echo -e "${BLUE}✨ Tip:${NC}"
echo -e "  less -R \"$REPORT_FILE\""
echo -e "  less -R \"$RAW_FILE\""
echo
