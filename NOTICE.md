# Licencias y atribución

El código propio de MokaReader (`iosApp/Sources/`, `iosApp/project.yml`, `.github/`) está bajo la
**Apache License 2.0** ([`LICENSE`](LICENSE)).

## Componentes reutilizados

| Componente | Origen | Licencia | Dónde |
|---|---|---|---|
| Host de extensiones JVM y shims de Android | [TachiyomiAZ](https://github.com/az4521/TachiyomiAZ) | Apache-2.0 | `Runtime/` |
| Scripts de build del runtime | TachiyomiAZ / tachiyomiazios | ver nota | `iosApp/Scripts/` |
| **TachiJVMRunner** (puente Swift/JNI) | TachiyomiAZ iOS | **GPL-3.0** | `iosApp/Packages/TachiJVMRunner/` |
| OpenJDK Mobile (Zero) | [openjdk/mobile](https://github.com/openjdk/mobile) | GPL-2.0 + Classpath Exception | se compila en CI |
| Suwayomi-Server (AndroidCompat) | [Suwayomi](https://github.com/Suwayomi/Suwayomi-Server) | MPL-2.0 | se compila en CI |

## Pendiente antes de publicar en el App Store

- **TachiJVMRunner es GPL-3.0.** Está incluido temporalmente para validar la app. Antes del envío
  a revisión hay que (a) pedirle a su autor (az4521) que lo relicencie como Apache-2.0, igual que
  `Runtime/`, o (b) reemplazarlo por un puente propio.
- `Scripts/build-openjdk-ios15.sh` y `Scripts/patches/openjdk-mobile-ios-runtime.patch` vienen de
  tachiyomiazios (GPL-3.0). El parche se aplica a OpenJDK, así que su licencia debe aclararse con el
  autor junto con el punto anterior.

MokaReader no aloja, incluye ni recomienda contenido ni repositorios de extensiones.
