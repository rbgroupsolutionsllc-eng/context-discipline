#!/usr/bin/env bash
# inject-discipline-rules.sh — Deploys context discipline rules across local AI agent CLIs.
# Supports: Claude Code, OpenCode, Codex CLI, Antigravity, and workspace AGENTS.md.
#
# Usage:
#   bash inject-discipline-rules.sh [global|workspace]

set -euo pipefail

MODE="${1:-global}"
TARGET_DIR="${2:-.}"

RULES_TEXT='<!-- CONTEXT-DISCIPLINE-START -->
# Context Discipline Rules (Mandatory)

## 1. Command Output Limits
Any command expected to output >100 lines must be redirected to disk, reporting only line count:
    <cmd> > /tmp/out.txt; wc -l /tmp/out.txt
Then read only the required snippet (grep, sed -n, head/tail). NEVER dump bulk logs, dumps, or verbose test suites into the context window.

## 2. Session Lifecycle
One session = One specific task.
When finished: update project state (e.g. ESTADO.md or README.md) and stop.
Do not continue unrelated tasks in the same session thread.

## 3. Working Scope
Never operate from $HOME directory. Always operate strictly from the project root.
<!-- CONTEXT-DISCIPLINE-END -->'

inject_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  if [[ -f "$file" ]] && grep -q "<!-- CONTEXT-DISCIPLINE-START -->" "$file"; then
    echo "  [up to date] $file"
  else
    echo -e "\n$RULES_TEXT" >> "$file"
    echo "  [injected]   $file"
  fi
}

echo "=== Context Discipline Rules Deployer ==="

if [[ "$MODE" == "workspace" ]]; then
  echo "Deploying to current workspace ($TARGET_DIR)..."
  inject_file "$TARGET_DIR/AGENTS.md"
  inject_file "$TARGET_DIR/CLAUDE.md"
else
  echo "Deploying globally to agent configs..."
  inject_file "$HOME/.claude/CLAUDE.md"
  inject_file "$HOME/.config/opencode/AGENTS.md"
  inject_file "$HOME/.codex/AGENTS.md"
  inject_file "$HOME/.gemini/config/rules/context-discipline.md"
fi

echo "Done! Context discipline rules successfully installed."
