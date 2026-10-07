/* =========================================================================
   APLICAR (*** MODIFICA DATOS ***) - quita rutas y equipos al personal de baja
   para que ninguna sincronización lo vuelva a cargar en los relojes.
   NO borra empleados. Guarda respaldo por lote en tablas zz_baja_*.
   El borrado en los relojes se hace después con scripts/Limpiar-UsuariosControlID.ps1

   ANTES: correr 01_vista_previa.sql con los mismos parámetros y hacer backup.
   ========================================================================= */

SET @legajos  = '1234';   -- piloto: '1234'   |   '' = TODAS las bajas
SET @excluir  = '';
SET @confirmo = 'NO';     -- hay que poner 'SI' para que modifique algo
SET @aplicar  = IF(@confirmo = 'SI', 1, 0);

/* --- candidatos (idéntico a la vista previa) --- */
DROP TEMPORARY TABLE IF EXISTS tmp_baja_personas;
CREATE TEMPORARY TABLE tmp_baja_personas AS
SELECT e.id_persona, e.legajo
FROM empleado e
WHERE e.estado = 2
  AND (@legajos = '' OR FIND_IN_SET(e.legajo, REPLACE(@legajos, ' ', '')) > 0)
  AND FIND_IN_SET(e.legajo, REPLACE(@excluir, ' ', '')) = 0
  AND NOT EXISTS (SELECT 1 FROM empleado e2
                  WHERE e2.id_persona <> e.id_persona AND e2.estado <> 2
                    AND ((e.dni <> '' AND e2.dni = e.dni) OR (e.id_reloj <> '' AND e2.id_reloj = e.id_reloj)))
  AND (   EXISTS (SELECT 1 FROM persona_ruta   pr WHERE pr.id_persona = e.id_persona)
       OR EXISTS (SELECT 1 FROM persona_equipo pe WHERE pe.id_persona = e.id_persona));

/* --- tablas de respaldo (se crean una sola vez) --- */
CREATE TABLE IF NOT EXISTS zz_baja_lote (lote VARCHAR(32) PRIMARY KEY, fecha DATETIME NOT NULL,
                                         parametros VARCHAR(4000), personas INT);
CREATE TABLE IF NOT EXISTS zz_baja_persona_ruta   (lote VARCHAR(32), id_persona BIGINT, id_ruta   BIGINT);
CREATE TABLE IF NOT EXISTS zz_baja_persona_equipo (lote VARCHAR(32), id_persona BIGINT, id_equipo BIGINT);

SET @lote = REPLACE(UUID(), '-', '');

START TRANSACTION;

INSERT INTO zz_baja_lote (lote, fecha, parametros, personas)
SELECT @lote, NOW(), CONCAT('legajos=', IF(@legajos = '', '(todos)', @legajos), '; excluir=', @excluir),
       (SELECT COUNT(*) FROM tmp_baja_personas)
FROM DUAL WHERE @aplicar = 1;

INSERT INTO zz_baja_persona_ruta (lote, id_persona, id_ruta)
SELECT @lote, pr.id_persona, pr.id_ruta
FROM persona_ruta pr JOIN tmp_baja_personas t ON t.id_persona = pr.id_persona
WHERE @aplicar = 1;

INSERT INTO zz_baja_persona_equipo (lote, id_persona, id_equipo)
SELECT @lote, pe.id_persona, pe.id_equipo
FROM persona_equipo pe JOIN tmp_baja_personas t ON t.id_persona = pe.id_persona
WHERE @aplicar = 1;

DELETE pr FROM persona_ruta pr
JOIN tmp_baja_personas t ON t.id_persona = pr.id_persona
WHERE @aplicar = 1;

DELETE pe FROM persona_equipo pe
JOIN tmp_baja_personas t ON t.id_persona = pe.id_persona
WHERE @aplicar = 1;

COMMIT;

SELECT 'resultado' AS paso,
       IF(@aplicar = 1, CONCAT('APLICADO - lote ', @lote), 'NO APLICADO: poner @confirmo = ''SI''') AS estado,
       (SELECT COUNT(*) FROM tmp_baja_personas) AS personas;
