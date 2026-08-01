# Forense de contexto por herramienta

Comandos para investigacion profunda cuando `audit-context.sh` marca una alarma.
Leer esto solo cuando haga falta ir mas alla del diagnostico automatico.

---

## Claude Code

Estado en `~/.claude/projects/<ruta-con-guiones>/`. Un `.jsonl` por sesion,
subagentes en `<session-id>/subagents/`.

```bash
# Ranking de proyectos
du -sh ~/.claude/projects/* | sort -h | tail -10

# Sesiones mas pesadas de un proyecto
find ~/.claude/projects/<PROY> -maxdepth 1 -name "*.jsonl" -printf '%s\t%p\n' | sort -rn | head -5

# Composicion de una sesion
F=<ruta.jsonl>
wc -l $F
python3 -c "
import json
from collections import Counter
c=Counter()
for l in open('$F'):
    try: c[json.loads(l).get('type','?')]+=1
    except: c['parse_error']+=1
print(c.most_common(10))
"
```

**Interpretacion.** `assistant` + `user` = turnos reales. Si un campo de metadata
(`ai-title`, `agent-name`, `mode`) aparece N veces, son N reanudaciones de la misma
sesion — cada `/resume` re-inyecta el bloque de arranque.

**Peso de subagentes:**
```bash
find ~/.claude/projects/<PROY> -path "*/subagents/*.jsonl" | wc -l
du -sh ~/.claude/projects/<PROY>/*/subagents 2>/dev/null | sort -h | tail -5
```
Si suman menos del 5% del total, no son la causa. Descartar y seguir.

**Uso real:** `/usage` dentro de Claude Code. Cubre solo la maquina local — otros
equipos y la web no aparecen ahi.

---

## OpenCode

SQLite unico en `~/.local/share/opencode/opencode.db` para todos los proyectos.
**Nunca moverlo ni borrarlo entero.**

```bash
DB=~/.local/share/opencode/opencode.db

# Detener procesos antes de escribir
pgrep -af opencode          # matar primero el supervisor (tmux), luego los hijos
cp $DB ~/opencode.db.bak

# Que tabla pesa
sqlite3 $DB "SELECT name, SUM(pgsize)/1024/1024 mb FROM dbstat GROUP BY name ORDER BY mb DESC LIMIT 10;"

# Ranking con directorio, costo y modelo
sqlite3 -header -column $DB "
SELECT substr(id,1,18) id, substr(directory,-32) dir,
       datetime(time_created/1000,'unixepoch') creada,
       tokens_cache_read/1000000 cr_M, ROUND(cost,2) usd,
       (SELECT COUNT(*) FROM message m WHERE m.session_id=s.id) msgs
FROM session s ORDER BY tokens_cache_read DESC LIMIT 10;"

# Sesiones de un repo
sqlite3 -header -column $DB "
SELECT substr(id,1,20) id, slug,
       (SELECT COUNT(*) FROM message m WHERE m.session_id=s.id) msgs
FROM session s WHERE directory LIKE '%<repo>%' ORDER BY time_updated DESC;"

# Borrado quirurgico — el PRAGMA es obligatorio
sqlite3 $DB "PRAGMA foreign_keys=ON; DELETE FROM session WHERE id='<ID>';"
sqlite3 $DB "SELECT COUNT(*) FROM message WHERE session_id='<ID>';"   # debe dar 0
```

Sin `PRAGMA foreign_keys=ON` el CASCADE no dispara y quedan huerfanos.

**Notas de esquema.** `session_context_epoch` tiene `session_id` como PRIMARY KEY:
una fila por sesion, no puede acumular historial. `time_compacting` es una bandera
de "en progreso", no un registro. **OpenCode no persiste rastro de que una
compactacion ocurrio** — el resumen entra como mensaje normal, indistinguible del
resto del hilo.

La tabla `event` suele dominar el archivo (append-only, guarda el contenido completo
del fragmento en cada actualizacion, no el delta). Eso es disco, no cuota. Borrar
sesiones no reduce el archivo sin `VACUUM`, que necesita espacio libre equivalente.

**Salidas de herramienta completas:** `~/.local/share/opencode/tool-output/`.
Guarda sin truncar lo que al contexto llego recortado.

---

## Codex

```bash
ls -la ~/.codex/
sqlite3 ~/.codex/logs_2.sqlite "SELECT name, SUM(pgsize)/1024/1024 mb FROM dbstat GROUP BY name ORDER BY mb DESC LIMIT 5;"
du -sh ~/.codex/{sessions,memories,attachments}
```

Un WAL grande frente a una tabla pequena indica falta de checkpoint. Diferencia
entre tamano de archivo y suma de tablas = paginas libres sin `VACUUM`.

---

## agy / Antigravity

```bash
AGY=~/.gemini/antigravity-cli
ls -lh $AGY/conversation_summaries.db
du -sh $AGY/{brain,knowledge,conversations}
sqlite3 $AGY/conversation_summaries.db ".tables"
```

---

## Bucle de compactacion — como reconocerlo

Patron observado en OpenCode, reproducible:

1. Salida de herramienta supera un limite fijo → truncacion
2. La truncacion dispara compactacion (**no** el tamano del contexto: se observo
   compactando al 4% de la ventana)
3. La compactacion genera un resumen estructurado que entra como contexto
4. El resumen es input del turno siguiente → vuelve a 1

**Es autosostenido porque el resumen nunca resuelve el truncamiento que lo causo.**
El agente registra "faltan N chars", reintenta, se trunca igual, compacta otra vez.

Firma diagnostica:
- `Compaction` con el contexto por debajo del 15%
- El mismo conteo de chars omitidos en reintentos sucesivos (corte determinista)
- `Next Move` identico entre turnos
- Bloques `Blocked` fabricados a partir de la ausencia de instruccion

**Corte:** interrumpir, cerrar la sesion, y ejecutar los comandos desde bash con
redireccion a disco. No negociar con la sesion — no sale del bucle.

---

## Orden de investigacion

Este orden refleja lo que funciono, no lo que parecia prometedor:

1. `du -sh` de los directorios de estado — 30 segundos, suele bastar
2. Conteo de turnos de la sesion mas pesada
3. Directorio de origen de esa sesion (`$HOME` es la señal fuerte)
4. Solo entonces: consultas SQL, composicion por tipo, plugins

Las hipotesis arquitectonicas (skills, plugins, fan-out, memoria en background)
son caras de investigar y en la auditoria original **cayeron todas**. Dejarlas
para el final, y solo si los pasos 1-3 no explican el consumo.
