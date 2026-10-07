# Caso de estudio: personal dado de baja que "volvía" a los relojes

> Caso real, anonimizado. No se incluyen nombres de la empresa ni de personas, direcciones de
> red ni detalles internos del software del proveedor.

## Contexto

Empresa industrial con unos 60 relojes de acceso y fichada **Control iD** (iDFace / iDFlex)
distribuidos en varias sedes. Los relojes los administra un **sistema de control de accesos**
que se sincroniza cada hora con el sistema de **RR.HH.** (alta de personal, egresos, tarjetas).
Cada persona tiene asignadas **rutas**, que son grupos de relojes, y el sistema de accesos
empuja a cada reloj los usuarios que le corresponden.

## El problema

- Los relojes acumulaban **cientos de personas dadas de baja**.
- Cuando se las borraba a mano en el equipo, **volvían a aparecer** en la siguiente sincronización.
- No había soporte del proveedor.

## Diagnóstico

Primero se entendió cómo funcionaba el sistema, sin tocar producción: análisis estático de sus
componentes (.NET y Java), de su configuración, de los logs de comunicación con los relojes y
de la base de datos, todo en modo de solo lectura. Hallazgos:

1. **Al egresar, el sistema solo deshabilita** al usuario en el reloj: nunca lo elimina.
2. **Quitarle la ruta tampoco lo elimina.** En los Control iD, la "baja" que llega al equipo solo
   borra tarjetas, roles y foto; el **usuario queda cargado**.
3. **El borrado en cola fallaba siempre.** La rutina que ejecuta las bajas pendientes estaba
   pensada para otra marca de relojes: consumía **dos elementos por vuelta** de un iterador y,
   con la única entrada que genera un Control iD, fallaba antes de enviar el borrado.
4. Mientras la persona siguiera asignada a sus rutas, cada sincronización la volvía a cargar.
   **Por eso el borrado manual no duraba.**
5. Los relojes trabajan en **modo push**: el servidor no conoce sus IPs, porque son ellos los
   que se conectan.
6. Problemas de datos que había que contemplar:
   - personas cargadas **dos veces** en el mismo reloj (una con el legajo y otra con el DNI como ID);
   - **traspasos** entre empresas del grupo: un legajo dado de baja y otro activo con el **mismo DNI**,
     que en el reloj son el mismo usuario;
   - la **Ñ dañada** en los nombres guardados en el reloj, y **nombres cortados** por el equipo;
   - relojes **sin número de serie** o con el **serial duplicado** en la base;
   - inactivos en RR.HH. **sin fecha de egreso**, que el sistema de accesos seguía tratando como activos.

## Estrategia

Ningún cambio sin poder verlo antes y deshacerlo después:

1. **Backup completo** de la base del sistema de accesos.
2. **Vista previa** de solo lectura: a quién se le quitarían rutas y de qué relojes.
3. **Piloto con una persona**, verificado de punta a punta (incluido que no volviera a cargarse).
4. **Cortar la recarga en el origen**: quitar rutas y equipos al personal de baja, con respaldo
   por lote para poder revertir y **protección de traspasos** (nunca tocar a quien comparte DNI
   o ID de reloj con un empleado activo).
5. **Eliminar directo en cada reloj** con su API HTTP (ver [`api-controlid.md`](api-controlid.md)):
   - búsqueda por ID de reloj y por DNI;
   - **confirmación por apellido y nombre** antes de borrar (tolerando la Ñ dañada, los nombres
     cortados y los duplicados de la misma persona);
   - borrado de credenciales, foto y **usuario**;
   - **nueva consulta** al reloj para confirmar que ya no está.
6. **Modo verificación por defecto**: el script solo informa, y para borrar hay que pasarle `-Borrar`.
7. **Pasadas sucesivas**: algunos relojes tenían otra contraseña de administración. El script es
   idempotente: una segunda pasada no vuelve a hacer lo ya hecho.
8. **Verificación posterior** y comparación persona por persona contra lo borrado.
9. **Informe final** con resultados, pendientes y acciones para RR.HH.

## Resultados

| | |
|---|---|
| Eliminaciones persona × reloj | **~1.080** |
| Personas eliminadas de al menos un reloj | **~215** |
| Relojes limpiados | **37** de ~60 |
| Errores al eliminar | **0** |
| Persistencia en relojes administrados por el sistema | **100 %** (nadie volvió a cargarse) |

La verificación posterior detectó además **dos relojes alimentados por otro programa** con su
propia copia de usuarios, que los reponía. La baja ahí corresponde a ese otro sistema.

Los relojes que no se pudieron procesar (sin conexión, sin IP conocida, otra contraseña o que
no son Control iD) quedaron documentados con el próximo paso para cada uno.

## Lecciones aprendidas

- **Atacar la causa, no el síntoma.** Borrar en el reloj sin cortar la sincronización no dura.
- **"No está" y "no pude consultar" no son lo mismo.** Una primera versión del script tomaba un
  error de consulta como "no está". Se corrigió para distinguirlos.
- **Confirmar la identidad antes de borrar.** Comparar el nombre evitó borrar IDs reutilizados.
  Los casos que la protección frenó resultaron ser duplicados de la misma persona, la Ñ dañada
  o nombres cortados, y el criterio se ajustó con esos ejemplos reales.
- **No confiar en los identificadores de los equipos.** Hubo relojes sin serial y con el serial
  duplicado: hay que agrupar por serial y nombre.
- **Timeouts reales.** Algunos equipos aceptan la conexión y nunca responden: una prueba previa
  del puerto, con límite de tiempo, evita que todo el proceso quede colgado.
- **Piloto, verificación y respaldo** hicieron posible corregir el rumbo varias veces sin riesgo.
- **Los datos de RR.HH. también tienen errores**: DNI duplicados entre personas distintas, egresos
  sin fecha, registros de prueba. El informe final los listó para su corrección.

## Próximos pasos

- Programar la limpieza para que corra sola cada noche.
- Reportar al proveedor los errores de borrado.
- Inventario de relojes: IP, serial y contraseña de administración, centralizados.
