# Licencias y atribución

El código propio de Wizard Cat Reader (`iosApp/Sources/`, `iosApp/Packages/WizardJVMRunner/`,
`iosApp/project.yml`, `.github/`) está bajo la **Apache License 2.0** ([`LICENSE`](LICENSE)).

## Componentes reutilizados

| Componente | Origen | Licencia | Dónde |
|---|---|---|---|
| Host de extensiones JVM y shims de Android | [TachiyomiAZ](https://github.com/az4521/TachiyomiAZ) | Apache-2.0 | `Runtime/` |
| Scripts de build del runtime | TachiyomiAZ / tachiyomiazios | ver nota | `iosApp/Scripts/` |
| **WizardJVMRunner** (puente Swift/JNI propio) | este repositorio | Apache-2.0 | `iosApp/Packages/WizardJVMRunner/` |
| Cabeceras JNI (`jni.h`, `jni_md.h`) | OpenJDK / Oracle | GPL-2.0 + Classpath Exception | dentro de WizardJVMRunner |
| OpenJDK Mobile (Zero) | [openjdk/mobile](https://github.com/openjdk/mobile) | GPL-2.0 + Classpath Exception | se compila en CI |
| Suwayomi-Server (AndroidCompat) | [Suwayomi](https://github.com/Suwayomi/Suwayomi-Server) | MPL-2.0 | se compila en CI |
| ZIPFoundation (lectura de CBZ) | [weichsel/ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | MIT | dependencia SPM |

WizardJVMRunner reemplaza al antiguo paquete GPL-3.0 TachiJVMRunner: fue escrito desde cero
contra la especificación JNI de Oracle y la interfaz Apache-2.0 de `app.tachiaz.compat.NativeBridge`
y `app.tachiaz.runtime.ExtensionHost` (lado Java de TachiyomiAZ).

## Nota pendiente

- `Scripts/build-openjdk-ios15.sh` y `Scripts/patches/openjdk-mobile-ios-runtime.patch` vienen de
  tachiyomiazios (GPL-3.0). Son herramientas de build (no se incluyen en el binario de la app),
  pero el parche modifica OpenJDK (GPL-2.0+CPE), así que conviene aclarar su licencia con el autor
  o reescribirlo.

Wizard Cat Reader no aloja, incluye ni recomienda contenido ni repositorios de extensiones.
