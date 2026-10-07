/* =========================================================================
   REVERTIR un lote de 02_aplicar.sql: restaura rutas y equipos.
   Las personas que ya se borraron de los relojes vuelven a cargarse recién
   cuando el sistema de accesos las sincronice de nuevo.
   ========================================================================= */

SET @lote = 'PEGAR_AQUI_EL_LOTE';

SELECT * FROM zz_baja_lote WHERE lote = @lote;   -- si no devuelve nada, el lote es incorrecto

START TRANSACTION;

INSERT INTO persona_ruta (id_persona, id_ruta)
SELECT z.id_persona, z.id_ruta FROM zz_baja_persona_ruta z
WHERE z.lote = @lote
  AND NOT EXISTS (SELECT 1 FROM persona_ruta pr WHERE pr.id_persona = z.id_persona AND pr.id_ruta = z.id_ruta);

INSERT INTO persona_equipo (id_persona, id_equipo)
SELECT z.id_persona, z.id_equipo FROM zz_baja_persona_equipo z
WHERE z.lote = @lote
  AND NOT EXISTS (SELECT 1 FROM persona_equipo pe WHERE pe.id_persona = z.id_persona AND pe.id_equipo = z.id_equipo);

COMMIT;

SELECT 'revertido' AS estado, @lote AS lote;
