---
name: context-discipline
description: Audita y corrige el consumo excesivo de tokens por contexto acumulado en agentes CLI (Claude Code, OpenCode, Codex, agy/Antigravity). Diagnostica sesiones infladas, salidas volcadas al contexto y estado persistente oculto, y propaga las reglas de disciplina a todas las herramientas. Usa esta skill SIEMPRE que el usuario mencione limites de uso, cuota agotada, sesiones lentas o caras, cache read alto, decidir entre planes de suscripcion, configurar una PC nueva, o cuando un agente ignore instrucciones y repita resumenes. Usala tambien de forma proactiva si detectas sesiones largas, comandos que vuelcan salidas grandes, o un agente corriendo desde $HOME.
---

# Disciplina de Contexto

Auditar y corregir el consumo de tokens causado por contexto acumulado en agentes CLI.

## Principio cero

**Mide antes de arreglar.**

El razonamiento sobre arquitectura es barato de producir y casi siempre equivocado.
En la auditoria que originó esta skill, cinco hipotesis arquitectonicas cayeron
(un skill de orquestacion, fan-out de subagentes, 22 plugins, subagentes, un observer
en background). La causa real salio de `du -sh` y una consulta SQL de 30 segundos:
**una sesion arrancada desde `$HOME`, reanudada 182 veces, hasta 3888 turnos.**

Ejecuta `scripts/audit-context.sh` ANTES de proponer cualquier cambio.

## Modelo mental

El contexto no se acumula, se **re-lee**. No existe "el agente ya sabe":
en cada turno se le vuelve a leer la transcripcion completa.
Costo = O(turnos x contexto). Cuadratico, no lineal.

Consecuencia menos obvia: el contexto viejo no solo cuesta, **compite** con la
instruccion entrante. Un agente con estado acumulado prefiere retomar su tarea
anterior antes que ejecutar lo que se le acaba de pedir.

## Flujo de trabajo

### 1. Diagnostico

```bash
bash scripts/audit-context.sh
```

Detecta que herramientas hay instaladas y reporta, por cada una: sesiones mas
pesadas, conteo de turnos, y estado persistente. No modifica nada.

Umbrales de alarma:

| Señal | Umbral | Significado |
|---|---|---|
| Turnos en una sesion | >400 | Sesion inflada |
| Directorio de proyecto = `$HOME` | cualquiera | Sin frontera de alcance |
| Salida de herramienta guardada | >50 KB | Volcado al contexto |
| Uso por encima de 150k de contexto | >80% | Arrastre dominante |

### 2. Confirmar antes de borrar

Nunca borres sin identificar primero. Pide confirmacion al usuario mostrando
que sesion, de que directorio, con cuantos turnos.

Preferir archivar sobre borrar:

```bash
mkdir -p ~/agent-archive
mv <archivo-de-sesion> ~/agent-archive/
```

Para OpenCode (SQLite), el `PRAGMA` es obligatorio o el CASCADE no dispara y
quedan huerfanos en `message` y `part`:

```bash
sqlite3 <db> "PRAGMA foreign_keys=ON; DELETE FROM session WHERE id='<ID>';"
```

Respaldar el `.db` completo antes de cualquier DELETE.

### 3. Propagar las reglas

Ver `references/rules-deployment.md` para las rutas por herramienta y el
procedimiento de anteponer sin destruir contenido existente.

### 4. Verificar

`/usage` dentro de Claude Code, una semana despues. Sesion por debajo del 90%
de forma sostenida = resuelto.

## Las reglas

### NUNCA

1. Arrancar un agente desde `$HOME` — sin raiz de proyecto nada acota el alcance ni define cuando termina la tarea
2. Reanudar una sesion pasados ~50 turnos
3. Volcar salida grande al contexto (logs, dumps, builds, tests verbose)
4. Mezclar tareas distintas en un mismo hilo
5. Aprobar plugins o servidores MCP "y todos los futuros"
6. Dejar creditos de uso abiertos sin tope de gasto

### SIEMPRE

1. `cd` al proyecto antes de abrir el agente
2. Redirigir salida grande a disco y reportar solo el conteo
3. Escribir `ESTADO.md` al cerrar, limpiar contexto al cambiar de tarea
4. Checkpoint cada ~2h en tareas largas
5. Revisar el uso una vez por semana

### El patron de oro

```bash
# MAL
rg -n "patron" -i

# BIEN
rg -n "patron" -i > /tmp/x.txt; wc -l /tmp/x.txt
# luego: sed -n '1,40p' /tmp/x.txt
```

**Corolario:** lo que se pueda hacer en bash, hazlo en bash. No gastes turnos de
agente para correr `rg` o `find`. Una recoleccion que fallo cinco horas dentro de
agentes se resolvio en tres segundos desde la terminal.

## ESTADO.md — el sustituto del hilo eterno

El argumento a favor del hilo largo es "asi el agente sabe todo lo que hicimos".
Falso: 40 lineas curadas superan a 3888 turnos de historia, porque la señal esta
limpia en vez de enterrada entre debugging y callejones sin salida.

```markdown
# <Proyecto> — Estado
Actualizado: YYYY-MM-DD

## Arquitectura vigente
## Congelado (no modificar)
## Decisiones tomadas
## En curso
## Descartado y por que
```

La seccion **"Descartado y por que"** es la de mayor valor: es lo unico del hilo
largo que un resumen normal pierde, y evita que cada agente nuevo re-proponga
lo mismo.

## Señales de alarma en vivo

Cuando aparezca cualquiera de estas, detener y arrancar sesion nueva:

- Compactacion disparandose con el contexto por debajo del 15%
- `Tool output truncated` repetido en el mismo punto
- Un bloque de estado (`Work State`, `Blocked`) que el usuario no pidio
- El agente pregunta en vez de ejecutar
- Un resumen que crece entre turnos en vez de encoger

Todas indican estado acumulado tomando el control sobre la instruccion entrante.

## Suscripciones

Un tier mas alto no arregla un problema de arquitectura de contexto: lo hace
mas caro mas lento. Empezar por el tier bajo, aplicar la disciplina, medir una
semana, y solo entonces decidir.

Distinguir los dos ejes: si la ventana corta se satura pero el limite semanal
esta holgado, el problema es arrastre por sesion, no volumen. Subir de tier
vende capacidad en ambos ejes cuando solo hace falta uno.

## Referencias

- `references/rules-deployment.md` — rutas de configuracion por herramienta y como propagar
- `references/forensics.md` — consultas SQL y comandos de diagnostico profundo por herramienta
- `scripts/audit-context.sh` — diagnostico automatico, solo lectura
