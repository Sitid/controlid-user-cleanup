/* =========================================================================
   VISTA PREVIA (SOLO LECTURA) - personal dado de baja que sigue con rutas/equipos
   No modifica nada: solo SELECT y tablas TEMPORALES.
   Esquema genérico de ejemplo: ver sql/README.md
   ========================================================================= */

SET @legajos = '';        -- ''  = todas las bajas   |   '1234,5678' = solo esos legajos
SET @excluir = '';        -- legajos a NO tocar aunque estén de baja (p.ej. a confirmar con RR.HH.)

/* 1) Candidatos: empleados de baja con rutas o equipos, salvo traspasos */
DROP TEMPORARY TABLE IF EXISTS tmp_baja_personas;
CREATE TEMPORARY TABLE tmp_baja_personas AS
SELECT e.id_persona, e.legajo, e.apellido, e.nombre, e.dni, e.id_reloj
FROM empleado e
WHERE e.estado = 2
  AND (@legajos = '' OR FIND_IN_SET(e.legajo, REPLACE(@legajos, ' ', '')) > 0)
  AND FIND_IN_SET(e.legajo, REPLACE(@excluir, ' ', '')) = 0
  /* traspasos: misma persona con otro legajo activo -> en el reloj es el mismo usuario */
  AND NOT EXISTS (SELECT 1 FROM empleado e2
                  WHERE e2.id_persona <> e.id_persona AND e2.estado <> 2
                    AND ((e.dni <> '' AND e2.dni = e.dni) OR (e.id_reloj <> '' AND e2.id_reloj = e.id_reloj)))
  AND (   EXISTS (SELECT 1 FROM persona_ruta   pr WHERE pr.id_persona = e.id_persona)
       OR EXISTS (SELECT 1 FROM persona_equipo pe WHERE pe.id_persona = e.id_persona));

/* 2) Relojes de cada persona (asignados + de sus rutas). En dos pasos por la
      limitación de MySQL con tablas temporales (ERROR 1137). */
DROP TEMPORARY TABLE IF EXISTS tmp_baja_equipos;
CREATE TEMPORARY TABLE tmp_baja_equipos (id_persona BIGINT NOT NULL, id_equipo BIGINT NOT NULL,
                                         PRIMARY KEY (id_persona, id_equipo));
INSERT IGNORE INTO tmp_baja_equipos
SELECT pe.id_persona, pe.id_equipo FROM persona_equipo pe JOIN tmp_baja_personas t ON t.id_persona = pe.id_persona;
INSERT IGNORE INTO tmp_baja_equipos
SELECT pr.id_persona, re.id_equipo FROM persona_ruta pr
JOIN ruta_equipo re ON re.id_ruta = pr.id_ruta
JOIN tmp_baja_personas t ON t.id_persona = pr.id_persona;

/* 3) Resultado */
SELECT 'resumen' AS paso,
       (SELECT COUNT(*) FROM tmp_baja_personas) AS personas,
       (SELECT COUNT(*) FROM tmp_baja_equipos)  AS persona_x_reloj;

SELECT 'excluidos_por_traspaso' AS paso, e.legajo, e.apellido, e.nombre, e2.legajo AS legajo_activo
FROM empleado e
JOIN empleado e2 ON e2.id_persona <> e.id_persona AND e2.estado <> 2
               AND ((e.dni <> '' AND e2.dni = e.dni) OR (e.id_reloj <> '' AND e2.id_reloj = e.id_reloj))
WHERE e.estado = 2
  AND (@legajos = '' OR FIND_IN_SET(e.legajo, REPLACE(@legajos, ' ', '')) > 0);

SELECT 'por_reloj' AS paso, q.nombre AS reloj, COUNT(*) AS personas
FROM tmp_baja_equipos eq JOIN equipo q ON q.id_equipo = eq.id_equipo
GROUP BY q.id_equipo, q.nombre
ORDER BY personas DESC;

SELECT 'fin' AS paso, 'VISTA PREVIA: no se modificó ninguna tabla' AS estado;
