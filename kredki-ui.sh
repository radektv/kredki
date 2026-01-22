#!/bin/bash
# ============================================================
#  K R E D K I  – Fast Secret Scanner for Linux
#  UI Wrapper (PRO+HTML+REPORT)
#
#  v1.8
#   FIXES (v1.8):
#    - HTML report generation is now reliable (no premature exit on bash arithmetic with set -e) ✅
#    - HTML generator is nounset-safe (set -u disabled only inside HTML render) ✅
#    - Security context blocks are precomputed & injected into HTML (Disk/Uptime/Network/Users now populated) ✅
#    - HTML <pre> blocks forced readable (light text on dark background) ✅
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

VERSION="1.8.4"
# Host identification (FQDN preferred)
HOST_FQDN="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo unknown-host)"
# Make it filename-safe
HOST_FQDN_SAFE="$(printf '%s' "$HOST_FQDN" | sed 's/[^A-Za-z0-9._-]/_/g')"


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

# Findings intelligence + permissions-aware risk
ENABLE_INTEL=true

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

# .kredkiignore (ignore by file/dir name, gitignore-like comments)
IGNORE_ENABLED=true
IGNORE_FILE_DEFAULT="$SCRIPT_DIR/.kredkiignore"
IGNORE_FILE=""
SHOW_IGNORED=false
IGNORE_PATTERNS=()

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

  --ignore-file <path>       Use custom .kredkiignore file
  --no-ignore                Disable .kredkiignore handling
  --show-ignored             Print loaded ignore patterns in config

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

get_os_pretty() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${PRETTY_NAME:-unknown}"
  else
    echo "unknown"
  fi
}

get_kernel() { uname -r 2>/dev/null || echo "unknown"; }

get_cpu_info() {
  local model cores
  model="$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^[ \t]*//')"
  cores="$(nproc 2>/dev/null || echo '?')"
  echo "${model:-unknown} (${cores} cores)"
}

get_ram_info() {
  # total and free in human friendly
  if command -v free >/dev/null 2>&1; then
    free -h | awk 'NR==2{printf "Total: %s | Used: %s | Free: %s | Available: %s\n",$2,$3,$4,$7}'
  else
    # fallback from /proc/meminfo
    local kb
    kb="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    echo "Total: $((kb/1024)) MB"
  fi
}

get_partitions() {
  # NOTE (v1.8.4): On some systems (e.g., RHEL with problematic/FUSE/CIFS mounts),
  # `df` may print useful output but exit with rc=1 (e.g. "Key has expired").
  # With `set -euo pipefail`, that rc=1 can abort the script and/or break report generation.
  # We therefore:
  #  - capture stdout regardless of rc (|| true)
  #  - silence stderr to avoid noisy mount errors in reports
  #  - always return 0 from this function (best-effort context block)
  local out=""
  out="$(df -hT 2>/dev/null || true)"
  if [[ -z "$out" ]]; then
    out="$(df -h 2>/dev/null || true)"
  fi
  printf '%s\n' "$out"
  return 0
}


get_uptime_pretty() {
  if command -v uptime >/dev/null 2>&1; then
    uptime -p 2>/dev/null || true
  fi
  # fallback
  if [[ -r /proc/uptime ]]; then
    local up s m h d
    up="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
    d=$((up/86400)); h=$(( (up%86400)/3600 )); m=$(( (up%3600)/60 ))
    if (( d > 0 )); then echo "up ${d} days, ${h} hours, ${m} minutes"; return; fi
    if (( h > 0 )); then echo "up ${h} hours, ${m} minutes"; return; fi
    echo "up ${m} minutes"
  else
    echo "unknown"
  fi
}

get_ip_brief() {
  if command -v ip >/dev/null 2>&1; then
    ip -br a 2>/dev/null || true
  else
    echo "ip tool not available"
  fi
}

get_users_summary() {
  echo "Current user: $(id -un 2>/dev/null || echo unknown) (uid=$(id -u 2>/dev/null || echo ?))"
  echo "Groups: $(id -Gn 2>/dev/null || true)"
  if command -v who >/dev/null 2>&1; then
    echo
    echo "Logged-in users (who):"
    who 2>/dev/null || true
  fi
  echo
  echo "Users with shells (from /etc/passwd):"
  awk -F: '($7 !~ /(nologin|false)$/){printf "%s (uid=%s, shell=%s)\n",$1,$3,$7}' /etc/passwd 2>/dev/null | head -n 30 || true
}

get_sudo_summary() {
  if command -v sudo >/dev/null 2>&1; then
    echo "sudo version: $(sudo -V 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -r /etc/sudoers ]]; then
    echo
    echo "/etc/sudoers (non-comment lines):"
    grep -E '^[[:space:]]*[^#[:space:]]' /etc/sudoers 2>/dev/null | head -n 80 || true
  fi
  if [[ -d /etc/sudoers.d ]]; then
    echo
    echo "/etc/sudoers.d (files):"
    ls -1 /etc/sudoers.d 2>/dev/null | head -n 50 || true
  fi
}

top_largest_files_with_findings() {
  local limit="${1:-10}"
  local tmp
  tmp="$(mktemp)"
  local f
  for f in "${!UNIQUE_FILES[@]}"; do
    [[ -e "$f" ]] || continue
    # size in bytes
    sz="$(stat -c '%s' "$f" 2>/dev/null || echo 0)"
    printf "%s\t%s\n" "$sz" "$f" >> "$tmp"
  done
  sort -nr "$tmp" | head -n "$limit"
  rm -f "$tmp"
}

human_bytes() {
  local b="${1:-0}"
  local kib=$((1024)); local mib=$((1024*1024)); local gib=$((1024*1024*1024))
  if (( b >= gib )); then awk -v b="$b" 'BEGIN{printf "%.2fG", b/1024/1024/1024}'; return; fi
  if (( b >= mib )); then awk -v b="$b" 'BEGIN{printf "%.2fM", b/1024/1024}'; return; fi
  if (( b >= kib )); then awk -v b="$b" 'BEGIN{printf "%.2fK", b/1024}'; return; fi
  printf "%sB" "$b"
}


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

trim_ws() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

load_kredkiignore() {
  IGNORE_PATTERNS=()
  [[ "$IGNORE_ENABLED" == "true" ]] || return 0

  local f="${IGNORE_FILE:-$IGNORE_FILE_DEFAULT}"
  [[ -f "$f" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(printf '%s' "$line" | trim_ws)"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    IGNORE_PATTERNS+=("$line")
  done < "$f"

  IGNORE_FILE="$f"
}

# Turn IGNORE_PATTERNS entries into ripgrep --glob excludes
# Matches are primarily by basename; directories are excluded recursively.
append_ignore_globs() {
  local p
  for p in "${IGNORE_PATTERNS[@]}"; do
    # if contains path separators, treat as path glob directly
    if [[ "$p" == *"/"* ]]; then
      RG_ARGS+=(--glob "!${p}")
      continue
    fi

    # wildcard / extension patterns: match by basename anywhere
    if [[ "$p" == *"*"* || "$p" == *"?"* || "$p" == *"["* ]]; then
      RG_ARGS+=(--glob "!**/${p}")
      continue
    fi

    # plain name: exclude files and directories with this name
    RG_ARGS+=(--glob "!**/${p}")
    RG_ARGS+=(--glob "!**/${p}/**")
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
  echo -e "🧠 Intel (tags/risk)   : ${ENABLE_INTEL}"
  echo -e "🔐 File metadata       : ${INCLUDE_FILE_METADATA}"
  echo -e "🧹 .kredkiignore       : ${IGNORE_ENABLED} ${IGNORE_FILE:+(${IGNORE_FILE})}"
  if [[ "$SHOW_IGNORED" == "true" && ${#IGNORE_PATTERNS[@]} -gt 0 ]]; then
    echo -e "${BOLD}🧹 Ignore patterns:${NC}"
    for p in "${IGNORE_PATTERNS[@]}"; do echo -e "  • $p"; done
  fi
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

# -------- Permissions-aware risk helpers --------
perm_flags() {
  # echo: flags + octal
  local f="$1"
  local oct
  oct="$(stat -c '%a' "$f" 2>/dev/null || echo '')"
  if [[ -z "$oct" || "$oct" == "?" ]]; then
    echo "unknown"
    return 0
  fi
  local special="0"
  local perms="$oct"
  if [[ ${#oct} -eq 4 ]]; then
    special="${oct:0:1}"
    perms="${oct:1:3}"
  fi
  local u="${perms:0:1}" g="${perms:1:1}" o="${perms:2:1}"
  local world_r=false group_r=false world_w=false suid=false sgid=false sticky=false
  (( o & 4 )) && world_r=true
  (( g & 4 )) && group_r=true
  (( o & 2 )) && world_w=true
  (( special & 4 )) && suid=true
  (( special & 2 )) && sgid=true
  (( special & 1 )) && sticky=true
  echo "world_r=${world_r} group_r=${group_r} world_w=${world_w} suid=${suid} sgid=${sgid} sticky=${sticky} octal=${oct}"
}

# -------- Finding intelligence (heuristics) --------
# Returns: TAGS|CONF|SEV (SEV 1..5)
classify_content() {
  local line="$1"
  local rest="${line#*:}"; rest="${rest#*:}"
  local c="$rest"

  local tags=()
  local conf="LOW"
  local sev=2

  if [[ "$c" =~ -----BEGIN[[:space:]](RSA|EC|OPENSSH|DSA)[[:space:]]PRIVATE[[:space:]]KEY----- ]]; then
    tags+=("PRIVATE_KEY"); conf="HIGH"; sev=5
  fi

  if [[ "$c" =~ \b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b ]]; then
    tags+=("GITHUB_TOKEN"); conf="HIGH"; sev=5
  fi

  if [[ "$c" =~ \b(AKIA|ASIA)[A-Z0-9]{16}\b ]]; then
    tags+=("AWS_ACCESS_KEY"); [[ "$conf" == "LOW" ]] && conf="MEDIUM"; (( sev < 4 )) && sev=4
  fi

  if [[ "$c" =~ ([A-Za-z0-9_-]{10,})\.([A-Za-z0-9_-]{10,})\.([A-Za-z0-9_-]{10,}) ]]; then
    tags+=("JWT"); [[ "$conf" == "LOW" ]] && conf="MEDIUM"; (( sev < 4 )) && sev=4
  fi

  if [[ "$c" =~ ([Aa]uthorization|[Bb]earer)[[:space:]]*[:=]?[[:space:]]*[Bb]earer[[:space:]]+[A-Za-z0-9._=-]{12,} ]]; then
    tags+=("BEARER_TOKEN"); [[ "$conf" == "LOW" ]] && conf="MEDIUM"; (( sev < 4 )) && sev=4
  fi

  if [[ "$c" =~ [A-Za-z0-9._%+-]{1,}:[^[:space:]]{1,}@ ]]; then
    tags+=("BASIC_AUTH"); [[ "$conf" == "LOW" ]] && conf="MEDIUM"; (( sev < 3 )) && sev=3
  fi

  if [[ "$c" =~ (password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]]{6,} ]]; then
    tags+=("CREDENTIAL"); [[ "$conf" == "LOW" ]] && conf="MEDIUM"; (( sev < 3 )) && sev=3
  fi

  if [[ "$c" =~ (kubeconfig|client-certificate-data|client-key-data|docker|auths|gcloud|azure|aws_) ]]; then
    tags+=("CLOUD"); (( sev < 3 )) && sev=3
  fi

  if (( ${#tags[@]} == 0 )); then
    tags=("MATCH"); conf="LOW"; sev=2
  fi

  local uniq=()
  local t
  for t in "${tags[@]}"; do
    if [[ " ${uniq[*]} " != *" ${t} "* ]]; then uniq+=("$t"); fi
  done

  local tag_str; tag_str="$(IFS=','; echo "${uniq[*]}")"
  echo "${tag_str}|${conf}|${sev}"
}

risk_score_for_file() {
  local file="$1" ctx="$2" sev="$3"
  local flags; flags="$(perm_flags "$file")"
  local score=0
  case "$ctx" in
    HIGH) score=$((score + 25)) ;;
    MEDIUM) score=$((score + 15)) ;;
    LOW) score=$((score + 5)) ;;
  esac
  score=$((score + sev * 10))
  if [[ "$flags" != "unknown" ]]; then
    [[ "$flags" == *"world_r=true"* ]] && score=$((score + 15))
    [[ "$flags" == *"group_r=true"* ]] && score=$((score + 8))
    [[ "$flags" == *"world_w=true"* ]] && score=$((score + 20))
    [[ "$flags" == *"suid=true"* ]] && score=$((score + 10))
    [[ "$flags" == *"sgid=true"* ]] && score=$((score + 6))
    [[ "$flags" == *"sticky=true"* ]] && score=$((score - 2))
  fi
  (( score > 100 )) && score=100
  (( score < 0 )) && score=0
  echo "$score"
}

risk_label() {
  local score="$1"
  if (( score >= 80 )); then echo "CRITICAL"; return; fi
  if (( score >= 60 )); then echo "HIGH"; return; fi
  if (( score >= 35 )); then echo "MEDIUM"; return; fi
  echo "LOW"
}

# Build "score<TAB>file" list sorted desc (requires FILE_RISK populated)
top_risk_list() {
  local limit="${1:-10}"
  local tmp
  tmp="$(mktemp)"
  local f s
  for f in "${!UNIQUE_FILES[@]}"; do
    s="${FILE_RISK[$f]:-0}"
    printf "%s\t%s\n" "$s" "$f" >> "$tmp"
  done
  sort -nr "$tmp" | head -n "$limit"
  rm -f "$tmp"
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
    --glob '!**/.kredkiignore'
  )

  [[ "$FOLLOW_SYMLINKS" == "true" ]] && RG_ARGS+=(--follow) || RG_ARGS+=(--no-follow)
  RG_ARGS+=("${EXCLUDE_GLOBS[@]}")
  # Apply .kredkiignore patterns
  if [[ "$IGNORE_ENABLED" == "true" && ${#IGNORE_PATTERNS[@]} -gt 0 ]]; then
    append_ignore_globs
  fi

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
# Intelligence per file
declare -A FILE_TAGS=()
declare -A FILE_CONF=()
declare -A FILE_SEV=()
declare -A FILE_RISK=()
declare -A FILE_CTX=()
declare -A FILE_FLAGS=()

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

    # Intelligence (tags/conf/severity) per match line -> aggregate per file
    if [[ "$ENABLE_INTEL" == "true" ]]; then
      local cls tag_str conf sev
      cls="$(classify_content "$m")"
      tag_str="${cls%%|*}"
      conf="${cls#*|}"; conf="${conf%%|*}"
      sev="${cls##*|}"

      if [[ -n "${FILE_TAGS[$file]:-}" ]]; then
        FILE_TAGS["$file"]="${FILE_TAGS[$file]},${tag_str}"
      else
        FILE_TAGS["$file"]="${tag_str}"
      fi

      if [[ -z "${FILE_SEV[$file]:-}" || "$sev" -gt "${FILE_SEV[$file]}" ]]; then
        FILE_SEV["$file"]="$sev"
      fi

      local cur="${FILE_CONF[$file]:-LOW}"
      case "$cur" in
        HIGH) : ;;
        MEDIUM) [[ "$conf" == "HIGH" ]] && FILE_CONF["$file"]="$conf" ;;
        LOW) FILE_CONF["$file"]="$conf" ;;
      esac
    fi

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
    # Finalize intelligence + risk per file
  if [[ "$ENABLE_INTEL" == "true" ]]; then
    local f
    for f in "${!UNIQUE_FILES[@]}"; do
      local ctx sev score flags
      ctx="$(ctx_for_path "$f")"
      sev="${FILE_SEV[$f]:-2}"
      score="$(risk_score_for_file "$f" "$ctx" "$sev")"
      flags="$(perm_flags "$f")"
      FILE_CTX["$f"]="$ctx"
      FILE_RISK["$f"]="$score"
      FILE_FLAGS["$f"]="$flags"

      local raw="${FILE_TAGS[$f]:-MATCH}"
      local IFS=','; read -r -a arr <<< "$raw"
      local uniq=()
      local t
      for t in "${arr[@]}"; do
        [[ -z "$t" ]] && continue
        if [[ " ${uniq[*]} " != *" ${t} "* ]]; then uniq+=("$t"); fi
      done
      FILE_TAGS["$f"]="$(IFS=','; echo "${uniq[*]}")"
      [[ -z "${FILE_CONF[$f]:-}" ]] && FILE_CONF["$f"]="LOW"
    done
  fi
done < "$raw_file" || true
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

  # Precompute system/context blocks defensively (avoid set -e aborting HTML generation)
  local os_pretty="" kernel="" cpu="" ram="" uptime="" ip="" users="" sudo_summary="" partitions=""
  os_pretty="$(get_os_pretty 2>/dev/null | html_escape || true)"
  kernel="$(get_kernel 2>/dev/null | html_escape || true)"
  cpu="$(get_cpu_info 2>/dev/null | html_escape || true)"
  ram="$(get_ram_info 2>/dev/null | html_escape || true)"
  uptime="$(get_uptime_pretty 2>/dev/null | html_escape || true)"
  ip="$(get_ip_brief 2>/dev/null | html_escape || true)"
  users="$(get_users_summary 2>/dev/null | html_escape || true)"
  sudo_summary="$(get_sudo_summary 2>/dev/null | html_escape || true)"
  partitions="$(get_partitions 2>/dev/null | html_escape || true)"

  : > "$report_file"
  chmod 600 "$report_file"

  {
    echo "KREDKI Report"
    echo "Version: $VERSION"
    echo "Release notes: v1.8 – HTML generation fixed (nounset-safe, populated context blocks, readable <pre>)"
    echo "Generated: $(date)"
    echo "Host (FQDN): ${HOST_FQDN}"
    echo "OS: $(get_os_pretty)"
    echo "Kernel: $(get_kernel)"
    echo "CPU: $(get_cpu_info)"
    echo "RAM: $(get_ram_info)"
    echo "Uptime: $(get_uptime_pretty)"
    echo "Profile: $PROFILE_NAME"
    echo "Scan paths: ${SCAN_PATHS[*]}"
    echo "Excluded paths: ${EXCLUDE_PATHS[*]}"
    echo "Auto-exclude project dir: $AUTO_EXCLUDE_PROJECT_DIR ($PROJECT_DIR)"
    echo "Context mode: $CONTEXT_MODE"
    echo "Redaction: TXT=$REDACT | HTML=$HTML_REDACT"
    echo "File metadata: $INCLUDE_FILE_METADATA"
    echo ".kredkiignore: $IGNORE_ENABLED ${IGNORE_FILE:+($IGNORE_FILE)}"
    if [[ "$IGNORE_ENABLED" == "true" && ${#IGNORE_PATTERNS[@]} -gt 0 ]]; then
      echo "Ignore patterns: $(IFS=,; echo ${IGNORE_PATTERNS[*]})"
    fi
    echo
    echo "Disk / partitions (df -hT)"
    echo "--------------------------"
    get_partitions
    echo
    echo "Network (ip -br a)"
    echo "---------------"
    get_ip_brief
    echo
    echo "Users (context)"
    echo "--------------"
    get_users_summary
    echo
    echo "Sudoers (context)"
    echo "----------------"
    get_sudo_summary
    echo
    echo "Summary"
    echo "------"
    echo "Total scan time: $(format_duration "$total_s")"
    echo "Total findings: $total_hits"
    if [[ "$ENABLE_INTEL" == "true" && "$total_hits" -gt 0 ]]; then
      echo
      echo "Top 10 risky files"
      echo "------------------"
      while IFS=$'\t' read -r s f; do
        label="$(risk_label "$s")"
        tags="${FILE_TAGS[$f]:-MATCH}"
        conf="${FILE_CONF[$f]:-LOW}"
        ctx="${FILE_CTX[$f]:-$(ctx_for_path "$f")}"
        printf "%3s/100  %-8s  %-6s  conf=%-6s  tags=%s\n      %s\n" "$s" "$label" "$ctx" "$conf" "$tags" "$f"
      done < <(top_risk_list 10) || true
      echo
      echo "Top 10 largest files with findings"
      echo "----------------------------------"
      while IFS=$'\t' read -r sz f; do
        printf "%8s  hits=%-4s  %s\n" "$(human_bytes "$sz")" "${FILE_HITS[$f]:-0}" "$f"
      done < <(top_largest_files_with_findings 10) || true
    fi
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
      echo "Files (unique) + access/ownership + risk"
      echo "-----------------------------------------"
      if [[ "$INCLUDE_FILE_METADATA" == "true" ]]; then
        for f in "${!UNIQUE_FILES[@]}"; do
          local ctx risk label tags conf flags
          ctx="${FILE_CTX[$f]:-$(ctx_for_path "$f")}"
          risk="${FILE_RISK[$f]:-0}"
          label="$(risk_label "$risk")"
          tags="${FILE_TAGS[$f]:-MATCH}"
          conf="${FILE_CONF[$f]:-LOW}"
          flags="${FILE_FLAGS[$f]:-unknown}"
          echo "$f"
          echo "  context: ${ctx} | tags: ${tags} | confidence: ${conf}"
          echo "  risk: ${risk}/100 (${label})"
          echo "  access: $(file_meta "$f")"
          echo "  perm_flags: ${flags}"
          echo "  hits: ${FILE_HITS["$f"]:-0}"
          echo
        done
      else
        for f in "${!UNIQUE_FILES[@]}"; do
          local ctx risk label tags conf
          ctx="${FILE_CTX[$f]:-$(ctx_for_path "$f")}"
          risk="${FILE_RISK[$f]:-0}"
          label="$(risk_label "$risk")"
          tags="${FILE_TAGS[$f]:-MATCH}"
          conf="${FILE_CONF[$f]:-LOW}"
          echo "$f (hits: ${FILE_HITS["$f"]:-0}) | ctx=${ctx} | risk=${risk}/100(${label}) | tags=${tags} | conf=${conf}"
        done
      fi

      echo
      echo "Findings (raw matches)"
      echo "---------------------"
      if [[ "$REDACT" == "true" ]]; then
        while IFS= read -r l; do
          [[ -z "$l" ]] && continue
          [[ "$l" == \[* ]] && continue
          if [[ "$ENABLE_INTEL" == "true" ]]; then
            local cls tag_str conf sev
            cls="$(classify_content "$l")"
            tag_str="${cls%%|*}"
            conf="${cls#*|}"; conf="${conf%%|*}"
            sev="${cls##*|}"
            printf "[TAGS:%s][CONF:%s][SEV:%s] %s\n" "$tag_str" "$conf" "$sev" "$(redact_line "$l")"
          else
            redact_line "$l"
          fi
        done < "$raw_file" || true
      else
        if [[ "$ENABLE_INTEL" == "true" ]]; then
          while IFS= read -r l; do
            [[ -z "$l" ]] && continue
            [[ "$l" == \[* ]] && continue
            local cls tag_str conf sev
            cls="$(classify_content "$l")"
            tag_str="${cls%%|*}"
            conf="${cls#*|}"; conf="${conf%%|*}"
            sev="${cls##*|}"
            printf "[TAGS:%s][CONF:%s][SEV:%s] %s\n" "$tag_str" "$conf" "$sev" "$l"
          done < "$raw_file" || true
        else
          cat "$raw_file"
        fi
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
    ((++count)); [[ $count -gt $max_show ]] && break
    local meta ctx risk tags conf flags label
    meta="$(file_meta "$f")"
    ctx="${FILE_CTX[$f]:-$(ctx_for_path "$f")}"
    risk="${FILE_RISK[$f]:-0}"
    label="$(risk_label "$risk")"
    tags="${FILE_TAGS[$f]:-MATCH}"
    conf="${FILE_CONF[$f]:-LOW}"
    flags="${FILE_FLAGS[$f]:-unknown}"

    printf '<tr><td><code>%s</code></td><td><code>%s</code></td><td><code>%s</code></td><td><code>%s</code></td><td>%s</td><td><code>%s</code></td></tr>\n' \
      "$(printf '%s' "$f" | html_escape)" \
      "$(printf '%s' "$meta" | html_escape)" \
      "$(printf '%s' "$ctx" | html_escape)" \
      "$(printf '%s' "risk=${risk}/100(${label}) | tags=${tags} | conf=${conf}" | html_escape)" \
      "${FILE_HITS["$f"]:-0}" \
      "$(printf '%s' "$flags" | html_escape)"
  done
}


generate_html_report() {
  # ---- HTML generation is best-effort: do not abort on `set -euo pipefail` edge cases (RHEL df exit codes, grep no-match, etc.) ----
  local __kredki_set_state
  __kredki_set_state="$(set +o)"
  set +e
  set +u
  set +o pipefail
  # Restore previous shell options on return
  trap 'eval "$__kredki_set_state"' RETURN

  local raw_file="$1" total_s="$2" html_out="$3"
local total_hits; total_hits="$(total_hits_from_file "$raw_file")"

# Precompute system/context blocks for HTML (these are shown in the dashboard).
# Important: do NOT allow failures here to abort report generation.
local os_pretty="" kernel="" cpu="" ram="" uptime="" ip="" users="" sudo_summary="" partitions=""
local __kredki_tmp=""

__kredki_tmp="$(get_os_pretty 2>/dev/null || true)";      os_pretty="$(printf '%s
' "$__kredki_tmp" | html_escape)"
__kredki_tmp="$(get_kernel 2>/dev/null || true)";        kernel="$(printf '%s
' "$__kredki_tmp" | html_escape)"
__kredki_tmp="$(get_cpu_info 2>/dev/null || true)";      cpu="$(printf '%s
' "$__kredki_tmp" | html_escape)"
__kredki_tmp="$(get_ram_info 2>/dev/null || true)";      ram="$(printf '%s
' "$__kredki_tmp" | html_escape)"
__kredki_tmp="$(get_uptime_pretty 2>/dev/null || true)"; uptime="$(printf '%s
' "$__kredki_tmp" | html_escape)"
__kredki_tmp="$(get_ip_brief 2>/dev/null || true)";      ip="$(printf '%s
' "$__kredki_tmp" | html_escape)"
__kredki_tmp="$(get_users_summary 2>/dev/null || true)"; users="$(printf '%s
' "$__kredki_tmp" | html_escape)"
__kredki_tmp="$(get_sudo_summary 2>/dev/null || true)";  sudo_summary="$(printf '%s
' "$__kredki_tmp" | html_escape)"
__kredki_tmp="$(get_partitions 2>/dev/null || true)";    partitions="$(printf '%s
' "$__kredki_tmp" | html_escape)"

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
    findings_raw="$(while IFS= read -r l; do [[ -z "$l" ]] && continue; [[ "$l" == \[* ]] && continue; if [[ "$ENABLE_INTEL" == "true" ]]; then cls="$(classify_content "$l")"; tag_str="${cls%%|*}"; conf="${cls#*|}"; conf="${conf%%|*}"; sev="${cls##*|}"; printf "[TAGS:%s][CONF:%s][SEV:%s] %s\n" "$tag_str" "$conf" "$sev" "$(redact_line "$l")"; else redact_line "$l"; fi; done < "$raw_file" | html_escape || true)"
  else
    findings_raw="$(if [[ "$ENABLE_INTEL" == "true" ]]; then while IFS= read -r l; do [[ -z "$l" ]] && continue; [[ "$l" == \[* ]] && continue; cls="$(classify_content "$l")"; tag_str="${cls%%|*}"; conf="${cls#*|}"; conf="${conf%%|*}"; sev="${cls##*|}"; printf "[TAGS:%s][CONF:%s][SEV:%s] %s\n" "$tag_str" "$conf" "$sev" "$l"; done < "$raw_file" | html_escape; else cat "$raw_file" | html_escape; fi || true)"
  fi

  local rules_html; rules_html="$(print_context_rules | html_escape | sed 's/$/<br>/' )"

  # Top 10 risky files rows
  local top_rows=""
  # Top 10 largest files with findings rows
  local largest_rows=""
  if [[ $total_hits -gt 0 ]]; then
    while IFS=$'\t' read -r sz f; do
      largest_rows+="<tr><td><code>$(human_bytes $sz)</code></td><td>${FILE_HITS[$f]:-0}</td><td><code>$(printf '%s' \"$f\" | html_escape)</code></td></tr>\\n"
    done < <(top_largest_files_with_findings 10) || true
  fi

  if [[ "$ENABLE_INTEL" == "true" && $total_hits -gt 0 ]]; then
    while IFS=$'\t' read -r s f; do
      label="$(risk_label "$s")"
      ctx="${FILE_CTX[$f]:-$(ctx_for_path "$f")}"
      conf="${FILE_CONF[$f]:-LOW}"
      tags="${FILE_TAGS[$f]:-MATCH}"
      top_rows+="<tr data-risk=\"$s\"><td><b>$s/100</b></td><td><code>$label</code></td><td><code>$ctx</code></td><td><code>$conf</code></td><td><code>$(printf '%s' \"$tags\" | html_escape)</code></td><td><code>$(printf '%s' \"$f\" | html_escape)</code></td></tr>\\n"
    done < <(top_risk_list 10) || true
  fi

  local meta_rows=""
  if [[ "$INCLUDE_FILE_METADATA" == "true" && $total_hits -gt 0 ]]; then
    meta_rows="$(html_meta_rows)"
  fi

  mkdir -p "$(dirname "$html_out")" 2>/dev/null || true
  : > "$html_out" 2>/dev/null || true
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
pre{background:#0b0f14 !important;color:#e6edf3 !important;border-radius:14px;padding:14px;overflow:auto;white-space:pre-wrap;word-break:break-word}
pre, pre code, pre span{color:#e6edf3 !important;}
.high{color:#b00020;font-weight:800}.med{color:#b26a00;font-weight:800}.low{color:#0b6e4f;font-weight:800}
.btns{display:flex;gap:10px;flex-wrap:wrap;margin-top:10px} button{border:1px solid #ddd;background:#fff;border-radius:10px;padding:8px 10px;cursor:pointer}
button:hover{background:#f7f7f7}
details{border:1px solid #eee;border-radius:14px;padding:12px;margin:10px 0;background:#fff} summary{cursor:pointer;font-weight:700}
ul{margin:10px 0 0 18px}
.warn{color:#7a4b00}
</style></head><body><div class="wrap">
<h1>🎨 KREDKI Report</h1>
<div class="muted">Generated: $(date) • Host: ${HOST_FQDN} • Version: ${VERSION} • Profile: ${PROFILE_NAME}</div>
  <div class="muted">Release notes: <b>v1.8</b> – HTML generation fixed (nounset-safe, populated context blocks, readable &lt;pre&gt;)</div>

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
    <button onclick="sortMetadataByRisk()">Sort metadata by risk</button>
  </div>
  <div class="muted" style="margin-top:10px">
    System: <b>${os_pretty}</b> • Kernel: <b>${kernel}</b><br>
    CPU: <b>${cpu}</b> • RAM: <b>${ram}</b><br>
    Context mode: <b>${CONTEXT_MODE}</b> • HTML redaction: <b>${HTML_REDACT}</b> • File metadata: <b>${INCLUDE_FILE_METADATA}</b>
  </div>
</div>

<div class="card"><h2>🏆 Top 10 risky files</h2>
<div class="muted">Ranked by risk score (context + severity + permissions). Redaction does not affect ranking.</div>
<table id="topRiskTable"><thead><tr><th>Risk</th><th>Label</th><th>Context</th><th>Confidence</th><th>Tags</th><th>File</th></tr></thead><tbody>
${top_rows:-<tr><td colspan="7" class="muted">No findings.</td></tr>}
</tbody></table>
</div>

</div>

<div class="card"><h2>🗄️ Disk / partitions</h2>
<div class="muted">Output of <code>df -hT</code> (tmpfs/devtmpfs excluded).</div>
<pre>${partitions}</pre>
</div>

<div class="card"><h2>⏳ Uptime</h2>
<pre>${uptime}</pre>
</div>

<div class="card"><h2>🌐 Network snapshot</h2>
<div class="muted">Output of <code>ip -br a</code>.</div>
<pre>${ip}</pre>
</div>

<div class="card"><h2>👥 Users (context)</h2>
<pre>${users}</pre>
</div>

<div class="card"><h2>🛂 Sudoers (context)</h2>
<pre>${sudo_summary}</pre>
</div>

<div class="card"><h2>📦 Top 10 largest files with findings</h2>
<div class="muted">Useful for triage. Sizes are current file sizes.</div>
<table><thead><tr><th>Size</th><th>Hits</th><th>File</th></tr></thead><tbody>
${largest_rows:-<tr><td colspan="3" class="muted">No findings.</td></tr>}
</tbody></table>
</div>

<div class="card"><h2>📂 Directories (time / hits)</h2>
<table><thead><tr><th>Directory</th><th>Time</th><th>Hits</th></tr></thead><tbody>
${dir_rows:-<tr><td colspan="7" class="muted">No directory stats available.</td></tr>}
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
<table id="metaTable"><thead><tr><th>Risk</th><th>File</th><th>Metadata (chmod / chown)</th><th>Context</th><th>Intel & Risk</th><th>Hits</th><th>Perm flags</th></tr></thead><tbody id="metaTbody">
${meta_rows:-<tr><td colspan="7" class="muted">File metadata disabled or no findings.</td></tr>}
</tbody></table></div>

<div class="card"><h2>🔎 Findings (raw matches)</h2>
<div class="muted">Tip: share the HTML report with redaction enabled.</div>
<pre>${findings_raw}</pre></div>

<div class="muted warn">⚠️ This report may contain sensitive data. Share carefully.</div>
</div>
<script>
function sortMetadataByRisk(){
  const tbody = document.getElementById("metaTbody");
  if(!tbody) return;
  const rows = Array.from(tbody.querySelectorAll("tr"));
  rows.sort((a,b)=> (parseInt(b.dataset.risk||"0",10) - parseInt(a.dataset.risk||"0",10)) );
  rows.forEach(r=>tbody.appendChild(r));
}

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
    --html) OVERRIDE_GENERATE_HTML=true; GENERATE_HTML=true; shift ;;
    --html-file) [[ $# -ge 2 ]] || die "--html-file requires a value"; OVERRIDE_HTML_FILE="$2"; GENERATE_HTML=true; shift 2 ;;
    --file-metadata) INCLUDE_FILE_METADATA=true; shift ;;
    --no-file-metadata) INCLUDE_FILE_METADATA=false; shift ;;
    --ignore-file) [[ $# -ge 2 ]] || die "--ignore-file requires a path"; IGNORE_FILE="$2"; shift 2 ;;
    --no-ignore) IGNORE_ENABLED=false; shift ;;
    --show-ignored) SHOW_IGNORED=true; shift ;;
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
load_kredkiignore

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
RAW_FILE="$SCRIPT_DIR/kredki_found_${HOST_FQDN_SAFE}_${TS}.raw.txt"
REPORT_FILE="$SCRIPT_DIR/kredki_found_${HOST_FQDN_SAFE}_${TS}.txt"

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
echo -e "🖥️  Host (FQDN): ${CYAN}${HOST_FQDN}${NC}"
echo -e "📁 Report TXT : ${CYAN}${REPORT_FILE}${NC}"
echo -e "📁 Raw matches: ${CYAN}${RAW_FILE}${NC}"
echo -e "⏱️  Total time : ${YELLOW}$(format_duration "$TOTAL_S")${NC}"
echo -e "🔐 Findings   : ${YELLOW}$(total_hits_from_file "$RAW_FILE")${NC}"

# Quick risk distribution
if [[ "$ENABLE_INTEL" == "true" ]]; then
  crit=0; high=0; med=0; low=0
  for f in "${!UNIQUE_FILES[@]}"; do
    score="${FILE_RISK[$f]:-0}"
    label="$(risk_label "$score")"
    case "$label" in
      CRITICAL) ((++crit)) ;;
      HIGH) ((++high)) ;;
      MEDIUM) ((++med)) ;;
      LOW) ((++low)) ;;
    esac
  done
  echo -e "🚦 Risk files : ${RED}CRIT ${crit}${NC} | ${YELLOW}HIGH ${high}${NC} | MED ${med} | LOW ${low}"
fi


# Optional HTML
if [[ "$GENERATE_HTML" == "true" ]]; then
  [[ -z "$HTML_FILE" ]] && HTML_FILE="${REPORT_FILE%.txt}.html"
  if generate_html_report "$RAW_FILE" "$TOTAL_S" "$HTML_FILE"; then
    if [[ -s "$HTML_FILE" ]]; then
      echo -e "📄 HTML       : ${CYAN}${HTML_FILE}${NC}"
    else
      echo -e "${YELLOW}[!]${NC} HTML generator ran but file is empty: ${CYAN}${HTML_FILE}${NC}"
    fi
  else
    echo -e "${YELLOW}[!]${NC} HTML generation failed. Check stderr output above."
  fi
fi

echo
echo -e "${BLUE}✨ Tip:${NC}"
echo -e "  less -R \"$REPORT_FILE\""
echo -e "  less -R \"$RAW_FILE\""
echo
