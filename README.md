# context-discipline

Skill para auditar y corregir consumo excesivo de tokens por contexto acumulado
en agentes CLI (Claude Code, OpenCode, Codex, agy/Antigravity).

## Uso

    bash scripts/audit-context.sh

Solo lectura. Detecta las herramientas instaladas y reporta sesiones infladas,
salidas volcadas al contexto y estado persistente.

## Instalacion

    git clone <url> ~/skills/context-discipline
    chmod +x ~/skills/context-discipline/scripts/audit-context.sh

Ver `references/rules-deployment.md` para desplegar las reglas en cada herramienta.
