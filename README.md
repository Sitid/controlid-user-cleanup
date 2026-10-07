# controlid-user-cleanup

Limpieza segura de usuarios dados de baja en relojes de acceso **Control iD** (iDFace / iDFlex /
FACE MAX), usando la API HTTP de los equipos, con modo verificación, confirmación por nombre y
verificación posterior.

> **TL;DR (EN):** PowerShell tool and SQL patterns to safely remove terminated employees from
> Control iD access-control terminals via their HTTP API: dry-run by default, identity check by
> name before deleting, post-delete verification, per-device logging and rollback-friendly
> workflow. Includes an anonymized case study (~1,080 removals across 37 devices, 0 errors).

## Por qué existe

Cuando el sistema que administra los relojes **no elimina** a las personas dadas de baja (solo las
deshabilita, o su rutina de borrado falla), los equipos acumulan usuarios que ya no deberían
estar, y borrarlos a mano no dura porque la siguiente sincronización los vuelve a cargar.
El caso completo, con el diagnóstico y las lecciones aprendidas, está en
[`docs/caso-de-estudio.md`](docs/caso-de-estudio.md).

La solución tiene dos partes:
1. **Cortar la recarga en el origen**: quitar rutas y equipos al personal de baja en la base del
   sistema de accesos. Hay un patrón SQL de ejemplo en [`sql/`](sql/).
2. **Eliminar a esas personas de cada reloj** con [`scripts/Limpiar-UsuariosControlID.ps1`](scripts/Limpiar-UsuariosControlID.ps1).

## Características del script

- **Solo verifica por defecto**: no borra nada sin `-Borrar`.
- **Busca** a cada persona por ID de reloj y por DNI (como `id` y como `registration`).
- **Confirma la identidad** antes de borrar: el nombre del reloj tiene que contener el apellido.
  - Tolera la **Ñ dañada** que devuelven algunos equipos.
  - Tolera **nombres cortados** por el reloj (si coincide el comienzo, con al menos 15 caracteres).
  - Borra **duplicados de la misma persona**, por ejemplo una carga con legajo y otra con DNI, solo si
    todos tienen exactamente el mismo nombre. Si no, lo marca para revisar a mano.
- **Borra** tarjetas, huellas, roles, grupos, foto y el usuario, y **vuelve a consultar** para
  confirmar que ya no está.
- **Distingue "no está" de "error al consultar"**.
- **Prueba la conexión** al puerto con timeout (3 s) antes de intentar, para no quedar colgado.
- `-Excluir` para saltear relojes, y `-Https` / `-Puerto` para equipos que no usan http:80.
- **Idempotente**: correrlo de nuevo, por ejemplo con otra contraseña de administración, no repite
  lo ya hecho.
- **Log CSV** con el resultado de cada persona × reloj, guardado al terminar cada reloj.

## Uso

Requisitos: Windows PowerShell 5.1 o PowerShell 7+, acceso de red a los relojes y un usuario
administrador de los equipos.

```powershell
# 1) Verificar (no borra nada)
powershell -ExecutionPolicy Bypass -File .\scripts\Limpiar-UsuariosControlID.ps1 `
    -Archivo .\ejemplos\usuarios_a_borrar.ejemplo.tsv -MapaIP .\ejemplos\relojes.ejemplo.csv

# 2) Borrar (después de revisar el resultado de la verificación)
powershell -ExecutionPolicy Bypass -File .\scripts\Limpiar-UsuariosControlID.ps1 `
    -Archivo .\usuarios.tsv -MapaIP .\relojes.csv -Excluir "Reloj sin respuesta" -Borrar
```

La contraseña de los relojes se pide en una ventana y no se guarda en ningún lado.

### Archivos de entrada

**Lista de personas por reloj** (TSV, separado por tabulaciones; ver
[`ejemplos/usuarios_a_borrar.ejemplo.tsv`](ejemplos/usuarios_a_borrar.ejemplo.tsv)):

| Columna | Descripción |
|---|---|
| `id_persona` | Legajo o identificador interno (para el reporte) |
| `apellido`, `nombre` | Se usan para confirmar la identidad |
| `id_reloj` | ID con el que el sistema carga a la persona en el reloj |
| `dni` | Documento (algunas instalaciones lo usan como ID) |
| `reloj` | Nombre del reloj |
| `serial` | Opcional |

**Mapa de IPs** (CSV separado por `;`; ver [`ejemplos/relojes.ejemplo.csv`](ejemplos/relojes.ejemplo.csv)):
columnas `reloj;serial;ip`. La IP se busca primero por nombre y después por serial.

### Resultado

`resultado_relojes_AAAAMMDD_HHMMSS.csv`, con una fila por persona × reloj:

| `accion` | Significado |
|---|---|
| `BORRARIA` | Encontrado y confirmado (modo verificación) |
| `BORRADO` | Eliminado y verificado |
| `NADA` + `NO ESTA EN EL RELOJ` | No estaba |
| `NADA` + `NO SE BORRA…` | El nombre no coincide: revisar a mano |
| `NADA` + `ERROR LOGIN` / `SIN CONEXION` / `SIN IP` / `EXCLUIDO` | No se pudo procesar ese reloj |
| `ERROR` | Falló el borrado o el usuario siguió en el reloj |

## Procedimiento recomendado

1. Backup de la base del sistema de accesos.
2. Vista previa ([`sql/01_vista_previa.sql`](sql/01_vista_previa.sql)).
3. Piloto con 1 o 2 personas: aplicar ([`sql/02_aplicar.sql`](sql/02_aplicar.sql)), exportar
   ([`sql/04_exportar_para_script.sql`](sql/04_exportar_para_script.sql)), verificar y borrar con el script.
4. Al día siguiente, confirmar que no volvieron a cargarse.
5. Corrida completa: verificación primero y, después de revisar el resultado, `-Borrar`.
6. Volver a verificar más tarde con la misma lista: todo debería dar "NO ESTA EN EL RELOJ".

## Seguridad y datos personales

- El repositorio **no contiene datos reales**. Los ejemplos usan nombres ficticios e IPs de los
  rangos reservados para documentación (RFC 5737).
- El `.gitignore` bloquea CSV, TSV, planillas, PDF y backups, para no subir listas reales por error.
- Las listas reales de personal tienen datos personales: tratarlas según la normativa vigente
  (en Argentina, Ley 25.326) y las políticas de la organización.

## Descargo

Proyecto independiente, sin relación con Control iD ni con ningún proveedor de software de
RR.HH. o control de accesos. Se usa bajo responsabilidad de quien lo ejecuta: probarlo siempre
primero en modo verificación y con un piloto.

## Licencia

[MIT](LICENSE)
