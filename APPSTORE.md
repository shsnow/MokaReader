# Ficha de App Store Connect — Wizard Cat Reader

Material listo para copiar/pegar en App Store Connect. Lo que va entre ⟨ ⟩ se completa a mano.

---

## Información de la app

| Campo | Valor |
|---|---|
| **Nombre** | Wizard Cat Reader |
| **Subtítulo** (≤30) | Tu biblioteca de manga |
| **Categoría principal** | Libros (Books) |
| **Categoría secundaria** | Entretenimiento |
| **Precio** | Gratis |
| **URL de soporte** | https://shsnow.github.io/MokaReader/ |
| **URL de privacidad** | https://shsnow.github.io/MokaReader/privacy.html |

> Las URLs funcionan tras activar GitHub Pages (ver al final). Si algún día renombras el repo,
> cambian solas de nombre — actualízalas en ASC.

## Texto promocional (≤170, editable sin nueva versión)

> Lector de manga y webtoons gratuito, sin publicidad y sin cuentas. Tu biblioteca, tus fuentes,
> tus reglas — y todo se queda en tu dispositivo.

## Descripción (español)

> Wizard Cat Reader es un lector de manga, manhwa y webtoons para iPhone y iPad: gratuito, sin
> publicidad, sin cuentas y sin recolección de datos.
>
> TU BIBLIOTECA
> • Organiza tus series con categorías, favoritos e insignias de capítulos sin leer.
> • "Seguir leyendo": retoma cualquier serie justo donde quedaste, con un toque.
> • Actualización de biblioteca con descarga automática opcional de capítulos nuevos.
>
> UN LECTOR HECHO PARA LEER
> • Modo webtoon vertical con desplazamiento continuo entre capítulos.
> • Autodesplazamiento con velocidad regulable: lectura manos libres.
> • Modo paginado izquierda→derecha o derecha→izquierda, con zoom y zonas de toque.
> • Descargas para leer sin conexión, donde sea.
>
> TUS FUENTES, TUS DATOS
> • Conecta tus propias fuentes y servidores autoalojados (por ejemplo Komga en tu red local).
>   La app no incluye, aloja ni recomienda contenido: tú decides qué agregar.
> • Copias de seguridad en formato abierto .tachibk, para llevarte tu biblioteca contigo.
> • Estadísticas de lectura calculadas en tu dispositivo.
>
> PARA TODA LA FAMILIA
> • El contenido marcado para adultos se bloquea de forma permanente y sin opción de activarlo.
>
> Wizard Cat Reader es software libre (Apache 2.0).

## Description (English)

> Wizard Cat Reader is a free manga, manhwa and webtoon reader for iPhone and iPad — no ads,
> no accounts, no data collection.
>
> YOUR LIBRARY
> • Categories, favorites and unread badges. • "Continue reading" row to resume any series in
> one tap. • Library updates with optional auto-download of new chapters.
>
> A READER BUILT FOR READING
> • Vertical webtoon mode with continuous scrolling across chapters. • Hands-free auto-scroll
> with adjustable speed. • Paged mode (LTR/RTL) with zoom and tap zones. • Offline downloads.
>
> YOUR SOURCES, YOUR DATA
> • Connect your own sources and self-hosted servers (e.g. Komga on your local network). The
> app includes, hosts and recommends no content — you decide what to add. • Open .tachibk
> backups. • On-device reading stats.
>
> FAMILY FRIENDLY
> • Adult-flagged content is permanently blocked, with no way to enable it.
>
> Wizard Cat Reader is open source (Apache 2.0).

## Keywords (≤100 caracteres)

```
manga,manhwa,webtoon,comic,lector,reader,komga,biblioteca,offline,descargas,tachibk
```

(No incluir nombres de otras apps — Apple rechaza metadata con marcas de terceros, regla 2.3.7.)

## Clasificación por edades (cuestionario)

Responder honesto; con fuentes agregadas por el usuario lo defendible es:

- Violencia de dibujos animados o fantasía: **Infrecuente/Moderada**
- Temas para adultos/sugerentes: **Infrecuente/Moderada**
- **Acceso web sin restricciones: SÍ** (las fuentes las agrega el usuario)
- Todo lo demás: No

→ Resultado esperado: **17+**. (El bloqueo +18 integrado es un plus que se menciona en las
notas al revisor, pero "acceso web sin restricciones" manda en el cuestionario.)

## App Privacy (sección de privacidad de datos)

- **Data Not Collected** (no se recolecta ningún dato) — coincide con la política publicada.

## Notas para el revisor (Review Notes, en inglés)

> Wizard Cat Reader is a reader app that ships with NO content and NO sources. Users connect
> their own self-hosted servers (such as Komga) or source repositories; the app itself
> includes, hosts and recommends none.
>
> Adult-flagged extensions and series are permanently blocked at multiple levels and this
> cannot be disabled by the user.
>
> To review the app's functionality, please use our demo server:
> ⟨URL del servidor Komga de demo⟩ — repository URL to paste in Extensions tab:
> ⟨URL del index del repo de demo⟩. It serves only public-domain comics.
>
> The app is free, has no ads, no purchases, no accounts, and collects no data.

### ⚠️ El riesgo real de la revisión: la demo

La app llega "vacía" al revisor (sin fuentes). Si el revisor no puede ver contenido,
puede rechazar por la regla 4.2 (funcionalidad mínima). Dos salidas:

1. **(Recomendada)** Montar un servidor Komga de demo con obras de dominio público
   (hay manga/cómics en dominio público en archive.org) y la extensión Komga de un
   repositorio que tú controles. Se lo pasamos al revisor en las notas.
2. Agregar soporte nativo de archivos locales CBZ (futura feature) para que la app
   funcione sin fuentes — más trabajo, pero elimina el problema de raíz.

## Capturas (desde tu iPhone, modo oscuro, series inofensivas en pantalla)

Se necesitan de 6.9" (iPhone Pro Max/Plus) o se reutilizan las del tamaño del 17 Pro:

1. Biblioteca con "Seguir leyendo" y categorías.
2. Lector en modo webtoon (página vistosa, sin contenido sensible).
3. Ficha de una serie con capítulos y botón Continuar.
4. Novedades con capítulos nuevos.
5. Descargas / lectura offline.
6. Ajustes (se ve el tema cálido y las opciones).

## Pasos de publicación (en orden)

1. GitHub → repo MokaReader → Settings → Pages → Source: "Deploy from a branch",
   Branch: `main`, carpeta `/docs` → Save. En ~2 min las URLs de arriba quedan vivas.
2. ASC → App Information → Name: "Wizard Cat Reader" (+ subtítulo).
3. ASC → App Privacy → "Data Not Collected".
4. Preparar la versión: descripción, keywords, URLs, capturas, clasificación.
5. Review Notes con el servidor de demo.
6. Enviar a revisión 🤞
