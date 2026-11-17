# Port Windows (C#) → iPad (Swift) — reglas comunes

La app iPad es una traducción fiel de `windows/` (rama `feature/windows-girth-movimiento`). Mismo comportamiento,
mismos textos en español, mismos formatos de archivo. Toda la lógica del núcleo vive en `ipad/AVOiPad/Core/` (mismo
target que la app, sin módulos: todo es visible sin `import`).

## Entorno
- Swift 5 (modo de lenguaje 5, Xcode 16/26), iOS/iPadOS 17+. Solo `Foundation`, `CryptoKit`, `Compression`,
  `CoreBluetooth`, `NetworkExtension`, `SwiftUI`, `Charts`, `MapKit`, `PDFKit`, `UIKit`. Sin dependencias externas.
- No hay compilador en la sesión de desarrollo: el código se compila en CI (macOS). Escribir Swift conservador:
  tipos explícitos en literales complejos, sin macros (`@Observable` sí se permite en la capa de UI), sin
  `if let x` abreviado dentro de expresiones complejas si complica la inferencia.

## Traducción de nombres
| C# | Swift |
|---|---|
| clase/record/enum `Foo` | mismo nombre `Foo` (sin prefijo). Clases estáticas → `enum Foo { static func … }` |
| `public sealed record` inmutable | `struct` (`Equatable`, `Hashable` si es útil; `Codable` si se serializa) |
| clase mutable con identidad (`TrainingSession`, cachés, clientes) | `final class` |
| propiedad `FooBar` | `fooBar` (lowerCamel). Acrónimos: `SessionId`→`sessionId`, `Sha256`→`sha256`, `GpsWeekMs`→`gpsWeekMs`, `ImuId`→`imuId`, `RtkName`→`rtkName`, `UtcTime`→`utcTime` |
| método `DoThing(x)` | `doThing(_ x:)` si el primer argumento es obvio; si no, etiquetas con el nombre del parámetro C# |
| enum `GnssSolution.RtkFix` | `GnssSolution.rtkFix` (con `Int` raw value si el C# tiene valores) |
| `double` / `int` / `long` / `ulong` / `byte` / `short` / `uint` | `Double` / `Int` / `Int64` / `UInt64` / `UInt8` / `Int16` / `UInt32` (`Int` cuando sea solo un contador o índice) |
| `double?` | `Double?` · `double.NaN` → `.nan` · `double.IsFinite` → `.isFinite` |
| `DateTimeOffset` | `Date` (hora mostrada siempre en `TimeZone(identifier: "Europe/Madrid")`, `Locale(identifier: "es_ES")`) |
| `List<T>` / `IReadOnlyList<T>` | `[T]` (en `final class`, `var` array) |
| `Dictionary<K,V>` | `[K: V]` |
| `byte[]` / `ReadOnlySpan<byte>` | `[UInt8]` o `Data` (usar `[UInt8]` para parsers binarios) |
| `InvalidDataException(msg)` | `throw AvoError.invalidData(msg)` |
| `FileNotFoundException` | `throw AvoError.notFound(msg)` |
| `InvalidOperationException(msg)` | `throw AvoError.invalidOperation(msg)` |
| `OperationCanceledException` | `throw CancellationError()` |
| otras excepciones propias (`ChestUsbException`, `NfcException`, `WatchException`…) | `struct XxxError: Error, LocalizedError` con los mismos campos |
| `CancellationToken` | `Task.checkCancellation()` / closure `isCancelled: () -> Bool` |
| `Path.Combine(a,b)` | `(a as NSString).appendingPathComponent(b)` (rutas como `String`, igual que en C#) |
| `%LOCALAPPDATA%\AVO Performance Horse\Windows` | `AppPaths.defaultRoot` = Application Support/`AVO Performance Horse/iPad` |
| `JsonSerializer` | `JSONEncoder/JSONDecoder` (+ `JSONSerialization` para JSON dinámico). Mismas claves que C# (C# serializa en PascalCase salvo `[JsonPropertyName]`: respetar las claves reales para que los JSON sean intercambiables con Windows) |
| `SHA256.HashData` | `CryptoKit.SHA256.hash(data:)`; hex en minúsculas con `AvoHex.lower(_:)` |
| `HMACSHA256` | `CryptoKit.HMAC<SHA256>` |
| `ZipFile` | `ZipReader` (Core/Zip.swift) |
| `string.Format("0.00")` | `AvoFormat.f(x, 2)` (coma decimal española, como `es-ES` en Windows) o `String(format:)` con `Locale(identifier: "es_ES")`. Para CSV/JSON/GPX: punto decimal invariable (`AvoFormat.inv(x, 2)`) |

## Utilidades compartidas (ya existen en `Core/Foundation.swift`)
`AvoError`, `AvoHex`, `AvoFormat`, `AvoTime` (zona Madrid, formatos `dd/MM/yyyy HH:mm`), `BinaryReaderLE`
(lectura little-endian sobre `[UInt8]`), `AvoJSON` (acceso seguro a `[String: Any]`).

## Archivos
Un archivo Swift por archivo C# del núcleo, con el mismo nombre (`RawReader.cs` → `Core/RawReader.swift`).
Comentarios: traducir los `/// <summary>` a `///` en español o inglés (como el original).

## Pruebas
`windows/AVO.Windows.SelfTest` → `ipad/AVOiPadTests` (XCTest). Mismos casos, mismos vectores
(`watch_vectors.json`, `usb_transcript.json` se copian como recursos de prueba).

## Fuera de alcance en iPad (decisión del usuario, 01/11/2026)
- **NFC**: el iPad no tiene NFC ni admite lectores PC/SC. Se conserva el UID guardado en cada ficha y el parser
  `avohorse://` (para pegar enlaces), pero no hay lectura ni grabación de etiquetas.
- **Reloj por USB**: iPadOS no da acceso a puertos serie USB. Se sustituye por la **descarga por Wi-Fi** del reloj
  (protocolo `firmware/chest/V3_7_4_WIFI/PROTOCOLO_WIFI.md`, BLE `WIFI_SYNC` + HTTP), igual que Android 2.3-wifi.
