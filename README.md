# Wizard Cat Reader

Wizard Cat Reader (antes MokaReader): lector de manga gratuito para iPhone y iPad, compatible con las extensiones de **Mihon**.

Las extensiones de Mihon (JARs de extension-lib 1.4–1.6) corren dentro de la app en una JVM
embebida (OpenJDK Mobile en modo intérprete) con la capa de compatibilidad Android de Suwayomi.

## Estado

- [x] Repositorios de extensiones (`index.pb`) e instalación de extensiones de Mihon
- [x] Explorar, ficha de serie, biblioteca (orden y columnas), notas por serie
- [x] Lector: webtoon/LTR/RTL, zoom, zonas de toque, fondo, margen webtoon, pantalla encendida
- [x] Descargas offline (simultáneas configurables, borrar al terminar)
- [x] Backups `.tachibk`: restaurar **y exportar** (compatible con Mihon)
- [x] Actividad: novedades de la biblioteca e historial de lectura
- [x] Contenido +18 bloqueado en todas las capas
- [x] Lector: scroll continuo entre capítulos (webtoon) y autoscroll con velocidad regulable
- [x] "Seguir leyendo" en la biblioteca y descarga automática de capítulos nuevos
- [x] Migración de series entre fuentes y filtros de búsqueda por fuente
- [ ] Doble página en el lector
- [ ] Trackers (AniList, MyAnimeList) y prioridad de scanlators
- [ ] Sincronización entre dispositivos (iCloud)
- [ ] Portadas personalizadas, íconos alternativos, pestañas configurables
- [ ] Recorte de bordes y acciones de Apple Pencil
- [ ] WebView para Cloudflare
- [x] Puente Swift/JNI propio (WizardJVMRunner, Apache-2.0) en lugar del paquete GPL

## Estructura

```
Runtime/                 Host Java de extensiones + shims (Apache-2.0, de TachiyomiAZ)
iosApp/
  Sources/App            Punto de entrada y pestañas
  Sources/Core           Modelos, biblioteca, ajustes, persistencia
  Sources/Engine         JVMEngine, repositorios, imágenes
  Sources/Views          Interfaz SwiftUI
  Packages/WizardJVMRunner  Puente Swift/JNI propio (Apache-2.0)
  Scripts/               Build de OpenJDK y del runtime
  project.yml            Proyecto XcodeGen
```

## Compilar

Sin Mac: **Actions → "iOS → TestFlight (firmado)" → Run workflow**. La primera corrida compila
OpenJDK desde fuente (~1 h); después queda en caché.
