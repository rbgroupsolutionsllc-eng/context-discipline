# Despliegue de reglas por herramienta

## Rutas

| Herramienta | Archivo global | Formato |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | Markdown plano |
| OpenCode | `~/.config/opencode/AGENTS.md` | Markdown plano |
| Codex | `~/.codex/AGENTS.md` | Markdown plano |
| agy / Antigravity | `~/.gemini/config/rules/<nombre>.md` | **Requiere frontmatter YAML** |

Codex y OpenCode tambien leen `AGENTS.md` por proyecto, que se combina con el global.
No hace falta tocar los de proyecto.

## Procedimiento

**Regla de oro: anteponer, nunca reemplazar.** Estos archivos suelen tener contenido
del usuario. Respaldar primero, siempre.

### 1. Archivo maestro

```bash
mkdir -p ~/.agent-rules
cat > ~/.agent-rules/CONTEXT-DISCIPLINE.md <<'EOF'
# Disciplina de contexto (obligatoria)

## Salida de comandos
Salida esperada mayor a 100 lineas: redirigir a disco y reportar solo el conteo.
    <cmd> > /tmp/x.txt; wc -l /tmp/x.txt
Luego leer solo el fragmento necesario (grep, sed -n, head).
Nunca volcar logs, dumps, builds ni tests verbose al contexto.

## Sesion
Una sesion = una tarea.
Al terminar: actualizar ESTADO.md en el repo y detenerse.
No continuar con una tarea distinta en el mismo hilo.

## Estado
Al arrancar: leer ESTADO.md del repo si existe.
Al cerrar: actualizarlo.

## Alcance
Nunca operar desde $HOME. Siempre desde la raiz del proyecto.
EOF
```

### 2. Claude Code — symlink

Es la unica que conviene enlazar: editar el maestro propaga solo.

```bash
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/CLAUDE.md.bak
ln -sf ~/.agent-rules/CONTEXT-DISCIPLINE.md ~/.claude/CLAUDE.md
```

Si habia contenido previo, fusionarlo al maestro:
```bash
cat ~/CLAUDE.md.bak >> ~/.agent-rules/CONTEXT-DISCIPLINE.md
```

### 3. OpenCode y Codex — anteponer

```bash
for f in ~/.config/opencode/AGENTS.md ~/.codex/AGENTS.md; do
  [ -f "$f" ] || continue
  cp "$f" "$f.bak"
  cat ~/.agent-rules/CONTEXT-DISCIPLINE.md "$f" > /tmp/merged.md
  mv /tmp/merged.md "$f"
done
```

Son copias, no symlinks: al cambiar el maestro hay que re-propagar.

### 4. agy — requiere frontmatter

Sin el bloque YAML la regla puede no registrarse.

```bash
mkdir -p ~/.gemini/config/rules
cat > ~/.gemini/config/rules/context-discipline.md <<'EOF'
---
name: context-discipline
description: Reglas OBLIGATORIAS de manejo de contexto. Evita volcar salidas grandes al contexto y limita el alcance de operacion. Previene el crecimiento descontrolado de sesiones y el consumo excesivo de tokens por relectura de contexto acumulado.
---

# DISCIPLINA DE CONTEXTO - REGLAS OBLIGATORIAS

## SALIDA DE COMANDOS
Salida esperada mayor a 100 lineas: redirigir a disco y reportar solo el conteo.
    <cmd> > /tmp/x.txt; wc -l /tmp/x.txt
Luego leer solo el fragmento necesario (grep, sed -n, head).
Nunca volcar logs, dumps, builds ni tests verbose al contexto.

## ALCANCE
Nunca operar desde $HOME. Siempre desde la raiz del proyecto.
EOF
```

## Verificacion

```bash
bash scripts/audit-context.sh   # la seccion final marca [ok] o [--]
```

## Limite conocido

Un archivo de reglas es una **sugerencia**, no enforcement. Se observo a un modelo
ignorar tres prompts consecutivos con las reglas cargadas.

Lo unico que produjo cumplimiento real fue codigo: un hook de inicio de sesion que
trunca la salida grande a disco automaticamente y muestra solo un preview. Si tras
una semana de medicion la disciplina por instruccion no baja el consumo, ahi se
justifica invertir en hooks — no antes.

## Alias defensivo (opcional)

Avisa en vez de arrancar cuando el directorio actual es `$HOME`:

```bash
echo 'alias claude="[ \"$PWD\" = \"$HOME\" ] && echo \"Estas en \$HOME — cd al proyecto\" || command claude"' >> ~/.bashrc
```

Probarlo desde `$HOME` y desde un proyecto antes de confiar en el.
