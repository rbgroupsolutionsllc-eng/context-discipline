#!/usr/bin/env bash
# audit-context.sh — Diagnostico de contexto acumulado en agentes CLI.
# SOLO LECTURA. No modifica ni borra nada.
#
# Uso: bash audit-context.sh

set -uo pipefail

TURN_ALARM=800          # turnos en una sesion
SIZE_ALARM=$((20*1024*1024))  # 20 MB por archivo de sesion
FOUND=0
ALARMS=0

hr() { printf '%.0s-' {1..60}; echo; }
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
echo "AUDITORIA DE CONTEXTO — $(date '+%Y-%m-%d %H:%M')"
echo "Host: $(hostname)"
hr

# ---------------------------------------------------------------- Claude Code
if [ -d "$HOME/.claude/projects" ]; then
  FOUND=1
  echo "CLAUDE CODE"
  echo "  Proyectos por tamano:"
  du -sh "$HOME"/.claude/projects/* 2>/dev/null | sort -h | tail -8 | sed 's/^/    /'

  # Sesion desde $HOME (sin raiz de proyecto)
  HOMEDIR="$HOME/.claude/projects/$(echo "$HOME" | tr '/' '-')"
  if [ -d "$HOMEDIR" ]; then
    SZ=$(du -sb "$HOMEDIR" 2>/dev/null | cut -f1)
    alarm "Hay sesiones arrancadas desde \$HOME ($(human "${SZ:-0}"))"
    echo "      -> $HOMEDIR"
  fi

  echo "  Sesiones individuales mas pesadas:"
  while IFS=$'\t' read -r sz path; do
    [ -n "${path:-}" ] || continue
    turns=$(wc -l < "$path" 2>/dev/null || echo 0)
    printf '    %-6s %6s turnos  %s\n' "$(human "$sz")" "$turns" "$(basename "$path")"
    if [ "$turns" -gt "$TURN_ALARM" ] || [ "$sz" -gt "$SIZE_ALARM" ]; then
      alarm "Sesion inflada: $(basename "$path") — archivar y arrancar limpio"
      echo "      -> $path"
    fi
  done < <(find "$HOME/.claude/projects" -maxdepth 2 -name "*.jsonl" -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -5)
  hr
fi

# -------------------------------------------------------------------- OpenCode
OC_DB="$HOME/.local/share/opencode/opencode.db"
if [ -f "$OC_DB" ]; then
  FOUND=1
  echo "OPENCODE"
  echo "  DB: $(human "$(stat -c%s "$OC_DB")")"
  WAL="${OC_DB}-wal"
  [ -f "$WAL" ] && echo "  WAL: $(human "$(stat -c%s "$WAL")")"

  if have sqlite3; then
    echo "  Top sesiones por cache read:"
    while IFS='|' read -r dir cr cost msgs; do
      [ -n "${dir:-}" ] || continue
      printf '    %-36s %5s M  %-8s %5s msgs\n' "$dir" "$cr" "$cost" "$msgs"
      [ "${msgs:-0}" -gt "$TURN_ALARM" ] && alarm "Sesion inflada en OpenCode: $dir ($msgs msgs)"
    done < <(sqlite3 -separator '|' "$OC_DB" "
      SELECT substr(directory,-34), tokens_cache_read/1000000,
             ROUND(cost,2),
             (SELECT COUNT(*) FROM message m WHERE m.session_id=s.id)
      FROM session s ORDER BY tokens_cache_read DESC LIMIT 6;" 2>/dev/null)

    HOMESESS=$(sqlite3 "$OC_DB" \
      "SELECT COUNT(*) FROM session WHERE directory='$HOME';" 2>/dev/null || echo 0)
    [ "${HOMESESS:-0}" -gt 0 ] && alarm "$HOMESESS sesion(es) de OpenCode arrancadas desde \$HOME"
  else
    alarm "sqlite3 no instalado — no se puede inspeccionar (sudo apt install sqlite3)"
  fi

  TO="$HOME/.local/share/opencode/tool-output"
  if [ -d "$TO" ]; then
    BIG=$(find "$TO" -type f -size +50k 2>/dev/null | wc -l)
    [ "$BIG" -gt 0 ] && alarm "$BIG salidas de herramienta >50KB — candidatas a volcado al contexto"
  fi
  hr
fi

# ----------------------------------------------------------------------- Codex
if [ -d "$HOME/.codex" ]; then
  FOUND=1
  echo "CODEX"
  for f in "$HOME"/.codex/*.sqlite; do
    [ -f "$f" ] || continue
    printf '    %-22s %s\n' "$(basename "$f")" "$(human "$(stat -c%s "$f")")"
    w="${f}-wal"
    if [ -f "$w" ]; then
      wsz=$(stat -c%s "$w")
      [ "$wsz" -gt 20971520 ] && alarm "WAL de $(basename "$f") en $(human "$wsz") sin checkpoint"
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
  echo "AGY / ANTIGRAVITY"
  for d in brain knowledge conversations; do
    [ -d "$AGY/$d" ] && printf '    %-16s %s\n' "$d/" "$(du -sh "$AGY/$d" 2>/dev/null | cut -f1)"
  done
  [ -f "$AGY/conversation_summaries.db" ] && \
    printf '    %-16s %s\n' "summaries.db" "$(human "$(stat -c%s "$AGY/conversation_summaries.db")")"
  hr
fi

# ------------------------------------------------------- Reglas desplegadas
echo "REGLAS DE DISCIPLINA"
check_rule() {
  local label=$1 path=$2
  if [ -e "$path" ] && grep -qi "disciplina de contexto\|context discipline" "$path" 2>/dev/null; then
    echo "    [ok]  $label"
  elif [ -e "$path" ]; then
    echo "    [--]  $label — existe pero sin las reglas"
  else
    echo "    [--]  $label — ausente"
  fi
}
check_rule "Claude Code" "$HOME/.claude/CLAUDE.md"
check_rule "OpenCode"    "$HOME/.config/opencode/AGENTS.md"
check_rule "Codex"       "$HOME/.codex/AGENTS.md"
check_rule "agy"         "$HOME/.gemini/config/rules/context-discipline.md"
hr

# ------------------------------------------------------------------- Resumen
if [ "$FOUND" -eq 0 ]; then
  echo "No se detecto ningun agente CLI conocido en este equipo."
  exit 0
fi

echo "RESUMEN: $ALARMS alarma(s)"
echo
if [ "$ALARMS" -gt 0 ]; then
  echo "Siguiente paso: revisar cada alarma con el usuario ANTES de tocar nada."
  echo "Archivar (mv) es preferible a borrar. Respaldar los .db antes de un DELETE."
else
  echo "Sin alarmas. Verificar el uso real con /usage dentro de Claude Code."
fi
echo
