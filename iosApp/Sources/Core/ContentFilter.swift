import Foundation

/// MokaReader is family friendly by design: adult content is not a setting, it is never shown.
///
/// Three layers, so one missing flag does not let anything through:
/// 1. Extensions marked NSFW or MIXED in the repository index never appear and cannot be installed.
/// 2. A downloaded JAR whose own manifest declares `nsfw` is rejected before it is kept.
/// 3. Individual series tagged with adult genres are hidden from every list and cannot be opened.
enum ContentFilter {
    /// Exact genre tags (case-insensitive) that mark a series as adult. Exact matching, so
    /// "Young Adult" or "Adventure" are not caught by "adult".
    private static let blockedGenres: Set<String> = [
        "adult", "adults only", "adulto", "adultos", "+18", "18+", "r-18", "r18",
        "hentai", "smut", "ecchi", "erotica", "erotic", "erótico", "erotico", "erotismo",
        "mature", "maduro", "pornographic", "porn", "nsfw", "sexual violence",
        "violencia sexual", "gore",
    ]

    static func isAllowed(_ manga: MangaItem) -> Bool {
        !manga.genres.contains { blockedGenres.contains($0.lowercased()) }
    }

    static func allowed(_ items: [MangaItem]) -> [MangaItem] {
        items.filter(isAllowed)
    }

    /// Mihon's content warning: 0 unspecified, 1 safe, 2 mixed, 3 NSFW.
    static func isAllowedExtension(contentWarning: UInt64) -> Bool {
        contentWarning < 2
    }

    /// The `tachiyomi.extension.nsfw` manifest value, as the JVM host reports it.
    static func manifestDeclaresAdult(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return value == "1" || value == "true"
    }
}
