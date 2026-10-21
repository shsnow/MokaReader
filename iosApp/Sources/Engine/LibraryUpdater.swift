import Combine
import Foundation

/// Refreshes every library entry against its source, one at a time — the extension engine is
/// serial anyway — and reports how many new chapters appeared.
@MainActor
final class LibraryUpdater: ObservableObject {
    static let shared = LibraryUpdater()

    @Published private(set) var isRefreshing = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var newChapters = 0
    @Published private(set) var lastFinished: Date?

    private var task: Task<Void, Never>?

    private init() {}

    func refreshAll(library: LibraryStore, extensions: ExtensionManager) {
        guard !isRefreshing else { return }
        let entries = library.sortedEntries
        guard !entries.isEmpty else { return }
        isRefreshing = true
        completed = 0
        newChapters = 0
        total = entries.count
        task = Task {
            for entry in entries {
                if Task.isCancelled { break }
                defer { self.completed += 1 }
                guard let installed = extensions.extensionFor(sourceId: entry.manga.sourceId) else {
                    continue
                }
                do {
                    let result = try await JVMEngine.shared.details(
                        of: entry.manga, installed: installed
                    )
                    let known = Set(entry.chapters.map(\.url))
                    self.newChapters += result.chapters.filter { !known.contains($0.url) }.count
                    library.refresh(result.manga, chapters: result.chapters)
                } catch {
                    // A source that is down should not stop the rest of the update.
                    continue
                }
            }
            self.isRefreshing = false
            self.lastFinished = Date()
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }
}
