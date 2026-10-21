import Combine
import Foundation

struct LibraryEntry: Codable, Hashable {
    var manga: MangaItem
    var chapters: [ChapterItem]
    var addedAt: Date
}

struct MangaProgress: Codable, Hashable {
    var readChapters: Set<String> = []
    var lastReadChapter: String?
    var lastReadAt: Date?
    var readingMode: ReadingMode?
}

/// The user's library and reading progress. Progress is kept for every manga opened, not only
/// those in the library, so reading something before saving it does not lose your place.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var entries: [String: LibraryEntry]
    @Published private(set) var progress: [String: MangaProgress]

    private static let libraryFile = "library.json"
    private static let progressFile = "progress.json"

    private init() {
        entries = Storage.load([String: LibraryEntry].self, from: Self.libraryFile) ?? [:]
        progress = Storage.load([String: MangaProgress].self, from: Self.progressFile) ?? [:]
    }

    var sortedEntries: [LibraryEntry] {
        entries.values.sorted {
            let left = progress[$0.manga.id]?.lastReadAt ?? $0.addedAt
            let right = progress[$1.manga.id]?.lastReadAt ?? $1.addedAt
            return left > right
        }
    }

    func contains(_ manga: MangaItem) -> Bool {
        entries[manga.id] != nil
    }

    func entry(for manga: MangaItem) -> LibraryEntry? {
        entries[manga.id]
    }

    func add(_ manga: MangaItem, chapters: [ChapterItem]) {
        entries[manga.id] = LibraryEntry(manga: manga, chapters: chapters, addedAt: Date())
        saveLibrary()
    }

    func remove(_ manga: MangaItem) {
        entries[manga.id] = nil
        saveLibrary()
    }

    /// Keeps a library entry's details and chapter list current after a refresh.
    func refresh(_ manga: MangaItem, chapters: [ChapterItem]) {
        guard var entry = entries[manga.id] else { return }
        entry.manga = manga
        if !chapters.isEmpty { entry.chapters = chapters }
        entries[manga.id] = entry
        saveLibrary()
    }

    func unreadCount(for entry: LibraryEntry) -> Int {
        let read = progress[entry.manga.id]?.readChapters ?? []
        return entry.chapters.filter { !read.contains($0.url) }.count
    }

    func isRead(_ chapter: ChapterItem, in manga: MangaItem) -> Bool {
        progress[manga.id]?.readChapters.contains(chapter.url) ?? false
    }

    func lastRead(in manga: MangaItem) -> String? {
        progress[manga.id]?.lastReadChapter
    }

    func setRead(_ read: Bool, chapter: ChapterItem, in manga: MangaItem) {
        var value = progress[manga.id] ?? MangaProgress()
        if read {
            value.readChapters.insert(chapter.url)
        } else {
            value.readChapters.remove(chapter.url)
        }
        progress[manga.id] = value
        saveProgress()
    }

    func markOpened(_ chapter: ChapterItem, in manga: MangaItem) {
        var value = progress[manga.id] ?? MangaProgress()
        value.lastReadChapter = chapter.url
        value.lastReadAt = Date()
        progress[manga.id] = value
        saveProgress()
    }

    func readingMode(for manga: MangaItem, fallback: ReadingMode) -> ReadingMode {
        if let stored = progress[manga.id]?.readingMode { return stored }
        return manga.looksLikeWebtoon ? .webtoon : fallback
    }

    func setReadingMode(_ mode: ReadingMode, for manga: MangaItem) {
        var value = progress[manga.id] ?? MangaProgress()
        value.readingMode = mode
        progress[manga.id] = value
        saveProgress()
    }

    private func saveLibrary() {
        Storage.save(entries, to: Self.libraryFile)
    }

    private func saveProgress() {
        Storage.save(progress, to: Self.progressFile)
    }
}
