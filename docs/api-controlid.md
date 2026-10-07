# Endpoints de la API de Control iD usados por el script

Todos se llaman con `POST` y cuerpo JSON (`Content-Type: application/json`). Después del login,
la sesión va como parámetro de la URL: `?session=<sesion>`. Los equipos suelen exponer la API en
`http://<ip>:80`; algunos solo en `https://<ip>:443`, con certificado autofirmado.

Referencia oficial: documentación de la API de acceso de Control iD.

| Endpoint | Cuerpo | Respuesta / uso |
|---|---|---|
| `/login.fcgi` | `{"login": "admin", "password": "…"}` | `{"session": "…"}` |
| `/load_objects.fcgi` | `{"object": "users", "where": {"users": {"id": 1001}}}` | `{"users": [ … ]}`: buscar al usuario por `id` |
| `/load_objects.fcgi` | `{"object": "users", "where": {"users": {"registration": "30111222"}}}` | buscar por matrícula |
| `/destroy_objects.fcgi` | `{"object": "cards", "where": {"cards": {"user_id": 1001}}}` | tarjetas de la persona (ídem `templates`, `user_roles`, `user_groups`) |
| `/user_destroy_image.fcgi` | `{"user_ids": [1001]}` | foto/rostro |
| `/destroy_objects.fcgi` | `{"object": "users", "where": {"users": {"id": 1001}}}` | `{"changes": 1}`: elimina el usuario |
| `/logout.fcgi` | `{}` | cierra la sesión |

## Observaciones prácticas

- Un `load_objects` sin resultados devuelve `{"users": []}`. Una falla de red o de sesión es una
  **excepción**: no hay que confundirla con "no está".
- Si la contraseña es incorrecta, el login falla enseguida con **401**. Si el equipo **no responde**,
  conviene probar antes el puerto con un timeout corto.
- Los equipos en **modo push** igual atienden la API web: el modo push define cómo el equipo habla
  con el servidor, no si acepta conexiones entrantes.
- El nombre (`name`) puede venir **cortado** o con caracteres dañados (por ejemplo la Ñ como `U+FFFD`).
