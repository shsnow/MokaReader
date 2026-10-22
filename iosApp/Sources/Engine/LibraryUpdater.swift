import Combine
import Foundation

/// Refreshes every library entry against its source, one at a time — the extension engine is
/// serial anyway — and remembers which chapters are new so the Novedades list can flag them.
@MainActor
final class LibraryUpdater: ObservableObject {
    static let shared = LibraryUpdater()

    @Published private(set) var isRefreshing = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var newChapters = 0
    @Published private(set) var lastFinished: Date?
    /// URLs of the chapters the latest update discovered.
    @Published private(set) var lastNewURLs: Set<String> = []

    private var task: Task<Void, Never>?
    private var cancelRequested = false

    private init() {}

    /// Fire-and-forget, for the toolbar button.
    func refreshAll(library: LibraryStore, extensions: ExtensionManager) {
        guard !isRefreshing else { return }
        task = Task { [weak self] in
            await self?.refresh(library: library, extensions: extensions)
            self?.task = nil
        }
    }

    /// Awaits until the whole update finishes, for pull-to-refresh.
    func refresh(library: LibraryStore, extensions: ExtensionManager) async {
        guard !isRefreshing else { return }
        let entries = library.sortedEntries
        guard !entries.isEmpty else { return }
        isRefreshing = true
        cancelRequested = false
        completed = 0
        newChapters = 0
        total = entries.count
        var discovered: Set<String> = []

        for entry in entries {
            if Task.isCancelled || cancelRequested { break }
            defer { completed += 1 }
            guard let installed = extensions.extensionFor(sourceId: entry.manga.sourceId) else {
                continue
            }
            do {
                let result = try await JVMEngine.shared.details(
                    of: entry.manga, installed: installed
                )
                let known = Set(entry.chapters.map(\.url))
                let fresh = result.chapters.filter { !known.contains($0.url) }
                newChapters += fresh.count
                discovered.formUnion(fresh.map(\.url))
                // Optional auto-download, oldest first so the queue follows reading order.
                // An entry with no chapter list yet is skipped: there "new" would mean the
                // whole series.
                if AppSettings.shared.autoDownloadUpdates, !known.isEmpty, !fresh.isEmpty {
                    DownloadManager.shared.enqueue(
                        Array(fresh.reversed()), manga: result.manga, installed: installed
                    )
                }
                library.refresh(result.manga, chapters: result.chapters)
            } catch {
                // A source that is down should not stop the rest of the update.
                continue
            }
        }
        if !discovered.isEmpty { lastNewURLs = discovered }
        isRefreshing = false
        lastFinished = Date()
    }

    func cancel() {
        cancelRequested = true
        task?.cancel()
    }
}
