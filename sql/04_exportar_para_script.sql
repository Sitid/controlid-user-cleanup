/* =========================================================================
   EXPORTAR (SOLO LECTURA) la lista persona x reloj de un lote, con las columnas
   que espera scripts/Limpiar-UsuariosControlID.ps1

   Ejemplo (MySQL, salida separada por tabulaciones):
     mysql --default-character-set=utf8 -B -u USUARIO -p BASE < 04_exportar_para_script.sql > usuarios.tsv
   ========================================================================= */

SET @lote = 'PEGAR_AQUI_EL_LOTE';

SELECT  e.legajo     AS id_persona,
        e.apellido,
        e.nombre,
        e.id_reloj,
        e.dni,
        q.nombre     AS reloj,
        q.serial
FROM (  -- relojes asignados + relojes de las rutas, según el respaldo del lote
        SELECT id_persona, id_equipo FROM zz_baja_persona_equipo WHERE lote = @lote
        UNION
        SELECT z.id_persona, re.id_equipo
        FROM zz_baja_persona_ruta z JOIN ruta_equipo re ON re.id_ruta = z.id_ruta
        WHERE z.lote = @lote
     ) x
JOIN empleado e ON e.id_persona = x.id_persona
JOIN equipo   q ON q.id_equipo  = x.id_equipo
ORDER BY q.nombre, e.legajo;
