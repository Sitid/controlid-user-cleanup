# SQL de ejemplo (patrón)

Estos scripts **no** corresponden a ningún producto en particular: usan un esquema genérico
para mostrar el patrón que se aplicó en el sistema de accesos real (MySQL 8). Hay que
adaptar nombres de tablas y columnas a la base de cada instalación.

## Esquema de ejemplo

| Tabla | Columnas | Qué representa |
|---|---|---|
| `empleado` | `id_persona`, `legajo`, `estado` (1 = activo, 2 = baja), `dni`, `id_reloj`, `apellido`, `nombre` | Personal sincronizado desde RR.HH. |
| `persona_ruta` | `id_persona`, `id_ruta` | Rutas (grupos de relojes) asignadas a cada persona |
| `ruta_equipo` | `id_ruta`, `id_equipo` | Relojes que componen cada ruta |
| `persona_equipo` | `id_persona`, `id_equipo` | Relojes asignados directamente |
| `equipo` | `id_equipo`, `nombre`, `serial` | Relojes |

## Orden de uso

1. `01_vista_previa.sql` (solo lectura): a quién se le quitarían rutas y equipos, y de qué relojes.
2. Backup completo de la base.
3. `02_aplicar.sql` con un piloto (`@legajos = '1234'`) y `@confirmo = 'SI'`: quita rutas y equipos,
   guarda un respaldo en tablas `zz_baja_*` e imprime un número de **lote**.
4. `04_exportar_para_script.sql` con ese lote: genera la lista persona × reloj para
   `scripts/Limpiar-UsuariosControlID.ps1`.
5. Si algo sale mal: `03_revertir.sql` con el lote.

## Decisiones que vale la pena copiar

- **Vista previa y aplicación en archivos separados.** La vista previa no crea ni modifica nada.
- **Doble llave para aplicar.** Un parámetro de piloto (`@legajos`) y un `@confirmo = 'SI'` explícito.
- **Protección de traspasos.** No se toca a nadie que comparta DNI o ID de reloj con un empleado
  activo: en el reloj es el mismo usuario.
- **Respaldo por lote** de todo lo que se quita, para poder revertir.
- **Limitación de MySQL:** una tabla temporal no puede referenciarse dos veces en la misma consulta
  (`ERROR 1137: Can't reopen table`). Por eso las uniones se cargan en dos `INSERT`.
