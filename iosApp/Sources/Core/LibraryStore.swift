import Combine
import Foundation

struct LibraryEntry: Codable, Hashable {
    var manga: MangaItem
    var chapters: [ChapterItem]
    var addedAt: Date
    var note: String? = nil
}

/// One "opened a chapter" event, newest first. The manga snapshot lets History navigate
/// even when the series is no longer in the library.
struct ReadingRecord: Codable, Hashable, Identifiable {
    var manga: MangaItem
    var chapterURL: String
    var chapterName: String
    var date: Date

    var id: String { "\(manga.id)#\(chapterURL)#\(date.timeIntervalSince1970)" }
}

struct BackupImportItem {
    var entry: LibraryEntry
    var progress: MangaProgress
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
    @Published private(set) var history: [ReadingRecord]

    private static let libraryFile = "library.json"
    private static let progressFile = "progress.json"
    private static let historyFile = "history.json"
    private static let historyLimit = 300

    private init() {
        entries = Storage.load([String: LibraryEntry].self, from: Self.libraryFile) ?? [:]
        progress = Storage.load([String: MangaProgress].self, from: Self.progressFile) ?? [:]
        history = Storage.load([ReadingRecord].self, from: Self.historyFile) ?? []
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

        // Reopening the same chapter refreshes its entry instead of stacking duplicates.
        if let first = history.first, first.manga.id == manga.id, first.chapterURL == chapter.url {
            history[0].date = Date()
        } else {
            history.insert(
                ReadingRecord(manga: manga, chapterURL: chapter.url, chapterName: chapter.name, date: Date()),
                at: 0
            )
            if history.count > Self.historyLimit {
                history.removeLast(history.count - Self.historyLimit)
            }
        }
        Storage.save(history, to: Self.historyFile)
    }

    func clearHistory() {
        history = []
        Storage.save(history, to: Self.historyFile)
    }

    func note(for manga: MangaItem) -> String {
        entries[manga.id]?.note ?? ""
    }

    func setNote(_ note: String, for manga: MangaItem) {
        guard var entry = entries[manga.id] else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmed.isEmpty ? nil : trimmed
        entries[manga.id] = entry
        saveLibrary()
    }

    /// A library entry's chapters stamped with their series, for the Novedades list.
    var latestUploads: [(manga: MangaItem, chapter: ChapterItem)] {
        entries.values
            .flatMap { entry in entry.chapters.map { (manga: entry.manga, chapter: $0) } }
            .filter { $0.1.dateUpload > 0 }
            .sorted { $0.1.dateUpload > $1.1.dateUpload }
            .prefix(150)
            .map { $0 }
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

    /// Merges a Mihon backup in one pass: existing read chapters are kept, the furthest
    /// history wins, and a reading mode already chosen in MokaReader is not overwritten.
    func applyImport(_ items: [BackupImportItem]) -> (added: Int, merged: Int) {
        var added = 0
        var merged = 0
        for item in items {
            let id = item.entry.manga.id
            if var existing = entries[id] {
                // What is already here was fetched live and is at least as current as the
                // backup, which may be months old: keep it, and only fill in a chapter list
                // that is missing entirely. Replacing a fresher list would drop chapters
                // added since the backup was taken.
                if existing.chapters.isEmpty { existing.chapters = item.entry.chapters }
                entries[id] = existing
                merged += 1
            } else {
                entries[id] = item.entry
                added += 1
            }
            var current = progress[id] ?? MangaProgress()
            current.readChapters.formUnion(item.progress.readChapters)
            if let at = item.progress.lastReadAt, at > (current.lastReadAt ?? .distantPast) {
                current.lastReadAt = at
                current.lastReadChapter = item.progress.lastReadChapter ?? current.lastReadChapter
            }
            if current.readingMode == nil { current.readingMode = item.progress.readingMode }
            progress[id] = current
        }
        saveLibrary()
        saveProgress()
        return (added, merged)
    }

    private func saveLibrary() {
        Storage.save(entries, to: Self.libraryFile)
    }

    private func saveProgress() {
        Storage.save(progress, to: Self.progressFile)
    }
}
