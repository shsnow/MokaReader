# MokaReader

Lector de manga gratuito para iPhone y iPad, compatible con las extensiones de **Mihon**.

Las extensiones de Mihon (JARs de extension-lib 1.4–1.6) corren dentro de la app en una JVM
embebida (OpenJDK Mobile en modo intérprete) con la capa de compatibilidad Android de Suwayomi.

## Estado

- [x] Repositorios de extensiones (`index.pb`) e instalación de extensiones
- [x] Explorar fuentes: populares, recientes y búsqueda
- [x] Ficha de la serie y lista de capítulos
- [x] Lector webtoon (vertical, a todo el ancho) y paginado izquierda→derecha / derecha→izquierda
- [x] Biblioteca y progreso de lectura
- [ ] Restaurar backups `.tachibk` de Mihon (núcleo Kotlin compartido)
- [ ] Descargas para leer sin conexión
- [ ] Trackers (AniList, MyAnimeList)
- [ ] WebView para Cloudflare
- [ ] Reemplazar/relicenciar TachiJVMRunner (ver `NOTICE.md`)

## Estructura

```
Runtime/                 Host Java de extensiones + shims (Apache-2.0, de TachiyomiAZ)
iosApp/
  Sources/App            Punto de entrada y pestañas
  Sources/Core           Modelos, biblioteca, ajustes, persistencia
  Sources/Engine         JVMEngine, repositorios, imágenes
  Sources/Views          Interfaz SwiftUI
  Packages/TachiJVMRunner  Puente Swift/JNI (temporal, GPL-3.0)
  Scripts/               Build de OpenJDK y del runtime
  project.yml            Proyecto XcodeGen
```

## Compilar

Sin Mac: **Actions → "iOS → TestFlight (firmado)" → Run workflow**. La primera corrida compila
OpenJDK desde fuente (~1 h); después queda en caché.
