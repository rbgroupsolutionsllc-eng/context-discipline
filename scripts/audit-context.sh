#!/usr/bin/env bash
# audit-context.sh — Forensic audit & token FinOps diagnostic for AI agent CLIs.
# READ-ONLY. Does not modify or delete any user files.
#
# Usage:
#   bash audit-context.sh

set -uo pipefail

TURN_ALARM=800                # alarm threshold for turns per session
SIZE_ALARM=$((20*1024*1024))  # 20 MB threshold per session file
FOUND=0
ALARMS=0
ESTIMATED_TOKENS=0

hr() { printf '%.0s-' {1..64}; echo; }
alarm() { echo "  [!] $1"; ALARMS=$((ALARMS+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

human() {
  local b=$1
  if   [ "$b" -ge 1073741824 ]; then echo "$((b/1073741824))G"
  elif [ "$b" -ge 1048576 ];    then echo "$((b/1048576))M"
  elif [ "$b" -ge 1024 ];       then echo "$((b/1024))K"
  else echo "${b}B"; fi
}

echo
echo "================================================================"
echo "          CONTEXT DISCIPLINE & TOKEN FINOPS AUDIT               "
echo "================================================================"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S') | Host: $(hostname)"
hr

# ---------------------------------------------------------------- Claude Code
if [ -d "$HOME/.claude/projects" ]; then
  FOUND=1
  echo "📦 CLAUDE CODE (Anthropic)"
  echo "  Projects by footprint:"
  du -sh "$HOME"/.claude/projects/* 2>/dev/null | sort -h | tail -8 | sed 's/^/    /'

  # Root directory session check
  HOMEDIR="$HOME/.claude/projects/$(echo "$HOME" | tr '/' '-')"
  if [ -d "$HOMEDIR" ]; then
    SZ=$(du -sb "$HOMEDIR" 2>/dev/null | cut -f1)
    alarm "Root session detected in \$HOME ($(human "${SZ:-0}")) — high token blast radius!"
    echo "      -> $HOMEDIR"
  fi

  echo "  Heaviest individual sessions:"
  while IFS=$'\t' read -r sz path; do
    [ -n "${path:-}" ] || continue
    turns=$(wc -l < "$path" 2>/dev/null || echo 0)
    # Estimate ~500 tokens per turn avg in raw JSONL
    ESTIMATED_TOKENS=$((ESTIMATED_TOKENS + turns * 500))
    printf '    %-6s %6s turns   %s\n' "$(human "$sz")" "$turns" "$(basename "$path")"
    if [ "$turns" -gt "$TURN_ALARM" ] || [ "$sz" -gt "$SIZE_ALARM" ]; then
      alarm "Bloated session: $(basename "$path") ($turns turns, $(human "$sz")) — archive to restore speed"
      echo "      -> $path"
    fi
  done < <(find "$HOME/.claude/projects" -maxdepth 2 -name "*.jsonl" -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -5)
  hr
fi

# -------------------------------------------------------------------- OpenCode
OC_DB="$HOME/.local/share/opencode/opencode.db"
if [ -f "$OC_DB" ]; then
  FOUND=1
  echo "⚡ OPENCODE (SST / CLI)"
  echo "  Database: $(human "$(stat -c%s "$OC_DB")")"
  WAL="${OC_DB}-wal"
  [ -f "$WAL" ] && echo "  WAL size: $(human "$(stat -c%s "$WAL")")"

  if have sqlite3; then
    echo "  Top sessions by cached token read:"
    while IFS='|' read -r dir cr cost msgs; do
      [ -n "${dir:-}" ] || continue
      printf '    %-36s %5s M tokens  \$%-6s %5s msgs\n' "$dir" "$cr" "$cost" "$msgs"
      [ "${msgs:-0}" -gt "$TURN_ALARM" ] && alarm "Bloated session in OpenCode: $dir ($msgs msgs)"
    done < <(sqlite3 -separator '|' "$OC_DB" "
      SELECT substr(directory,-34), ROUND(tokens_cache_read/1000000.0, 1),
             ROUND(cost,2),
             (SELECT COUNT(*) FROM message m WHERE m.session_id=s.id)
      FROM session s ORDER BY tokens_cache_read DESC LIMIT 6;" 2>/dev/null)

    HOMESESS=$(sqlite3 "$OC_DB" \
      "SELECT COUNT(*) FROM session WHERE directory='$HOME';" 2>/dev/null || echo 0)
    [ "${HOMESESS:-0}" -gt 0 ] && alarm "$HOMESESS OpenCode session(s) started from \$HOME"
  else
    alarm "sqlite3 not installed — run: sudo apt install sqlite3"
  fi

  TO="$HOME/.local/share/opencode/tool-output"
  if [ -d "$TO" ]; then
    BIG=$(find "$TO" -type f -size +50k 2>/dev/null | wc -l)
    [ "$BIG" -gt 0 ] && alarm "$BIG tool outputs >50KB — potential context flooding"
  fi
  hr
fi

# ----------------------------------------------------------------------- Codex
if [ -d "$HOME/.codex" ]; then
  FOUND=1
  echo "🤖 OPENAI CODEX CLI"
  for f in "$HOME"/.codex/*.sqlite; do
    [ -f "$f" ] || continue
    printf '    %-22s %s\n' "$(basename "$f")" "$(human "$(stat -c%s "$f")")"
    w="${f}-wal"
    if [ -f "$w" ]; then
      wsz=$(stat -c%s "$w")
      [ "$wsz" -gt 20971520 ] && alarm "WAL of $(basename "$f") is $(human "$wsz") without checkpoint"
    fi
  done
  [ -d "$HOME/.codex/sessions" ] && echo "    sessions/  $(du -sh "$HOME/.codex/sessions" 2>/dev/null | cut -f1)"
  [ -d "$HOME/.codex/memories" ] && echo "    memories/  $(du -sh "$HOME/.codex/memories" 2>/dev/null | cut -f1)"
  hr
fi

# ------------------------------------------------------------ agy / Antigravity
AGY="$HOME/.gemini/antigravity-cli"
if [ -d "$AGY" ]; then
  FOUND=1
  echo "🪐 ANTIGRAVITY / AGY (Google DeepMind)"
  for d in brain knowledge conversations; do
    [ -d "$AGY/$d" ] && printf '    %-16s %s\n' "$d/" "$(du -sh "$AGY/$d" 2>/dev/null | cut -f1)"
  done
  [ -f "$AGY/conversation_summaries.db" ] && \
    printf '    %-16s %s\n' "summaries.db" "$(human "$(stat -c%s "$AGY/conversation_summaries.db")")"
  hr
fi

# ------------------------------------------------------- IDE Workspaces
if [ -d "$HOME/.cursor" ] || [ -d "$HOME/.codeium/windsurf" ]; then
  echo "💻 IDE WORKSPACES"
  [ -d "$HOME/.cursor" ] && echo "    Cursor cache:   $(du -sh "$HOME/.cursor" 2>/dev/null | cut -f1)"
  [ -d "$HOME/.codeium/windsurf" ] && echo "    Windsurf cache: $(du -sh "$HOME/.codeium/windsurf" 2>/dev/null | cut -f1)"
  hr
fi

# ------------------------------------------------------- Deployed Rules Check
echo "🛡️ CONTEXT DISCIPLINE GOVERNANCE"
check_rule() {
  local label=$1 path=$2
  if [ -e "$path" ] && grep -qi "disciplina de contexto\|context discipline" "$path" 2>/dev/null; then
    echo "    [ACTIVE]   $label ($path)"
  elif [ -e "$path" ]; then
    echo "    [INACTIVE] $label — file exists but missing context discipline headers"
  else
    echo "    [MISSING]  $label — no configuration file found"
  fi
}
check_rule "Claude Code" "$HOME/.claude/CLAUDE.md"
check_rule "OpenCode"    "$HOME/.config/opencode/AGENTS.md"
check_rule "Codex"       "$HOME/.codex/AGENTS.md"
check_rule "Antigravity" "$HOME/.gemini/config/rules/context-discipline.md"
hr

# ------------------------------------------------------------------- Summary
if [ "$FOUND" -eq 0 ]; then
  echo "No known AI agent CLI installations detected on this machine."
  exit 0
fi

echo "📊 AUDIT SUMMARY: $ALARMS alarm(s) triggered"
echo

if [ "$ALARMS" -gt 0 ]; then
  echo "🚨 ACTION REQUIRED:"
  echo "  1. Archive overgrown session logs (.jsonl / sqlite) to recover sub-second speed."
  echo "  2. Deploy context rules using: bash scripts/inject-discipline-rules.sh global"
  echo "  3. Enforce: 'Command output >100 lines -> redirect to disk; report only line count'."
else
  echo "✅ HEALTHY: All agent environments follow compact token discipline."
fi
echo
