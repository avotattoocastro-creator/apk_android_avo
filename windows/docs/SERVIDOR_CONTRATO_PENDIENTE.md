# Servidor AVO — contrato pendiente (Windows V2 PRO)

**Estado: NO CONECTADO.** No existe en el repositorio ningún contrato verificado de `https://live.avoperformance.org`
(`core/.../server/ServerApi.kt` está «ON HOLD» y solo enumera rutas históricas cuyo formato se desconoce). La aplicación
Windows **no inventa endpoints, autenticación ni respuestas**.

## Lo que sí funciona hoy
- Abrir el panel web en el navegador.
- Descarga manual de un `.avo` por HTTPS (máx. 100 MB) → validación completa (manifiesto, SHA-256 por segmento, CRC) →
  biblioteca local con detección de duplicados por SHA-256 del archivo y por `sessionId`.
- Uso sin conexión con la biblioteca local.

## Interfaz preparada en el código
`windows/AVO.Windows.Core/Services/Services.cs` → `IAvoServerClient`:

| Operación | Firma | Necesita del servidor |
|---|---|---|
| Estado | `ServerState State`, `string StatusText` | — |
| Listar sesiones del usuario autenticado | `Task<IReadOnlyList<RemoteSession>> ListSessionsAsync(ct)` | endpoint de listado, paginación, campos `id`, caballo, jinete, inicio UTC, `sha256` del paquete, tamaño |
| Descargar | `Task<string> DownloadAsync(RemoteSession, dir, progress, ct)` | URL de descarga por id, soporte `Range` para reanudar, hash publicado |

Implementación actual: `PendingContractServerClient` (todas las operaciones informan «contrato pendiente»).

## Datos que hay que acordar antes de conectar
1. Método de autenticación (p. ej. OAuth 2.0 con PKCE o token personal) y dónde se guarda el secreto
   (Windows Credential Manager / DPAPI; **nunca** en el repositorio ni en `ajustes.json`).
2. Esquema JSON del listado y códigos de error.
3. Hash publicado por el servidor: ¿SHA-256 del ZIP `.avo` o hash canónico del reloj? (no son lo mismo).
4. Política de duplicados y de versiones de una misma sesión.
5. Límites de tamaño y de frecuencia.

Cuando el contrato exista, se añadirá una implementación `AvoServerClient : IAvoServerClient` con pruebas contra un servidor
simulado, sin cambiar las vistas.
