import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""

    private var items: [LibraryEntry] {
        let all = library.sortedEntries
        guard !query.isEmpty else { return all }
        return all.filter { $0.manga.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if library.entries.isEmpty {
                EmptyStateView(
                    symbol: "books.vertical",
                    title: "Tu biblioteca está vacía",
                    message: "Busca algo en Explorar y toca el marcador para guardarlo aquí."
                )
            } else {
                MangaGrid(
                    items: items.map(\.manga),
                    badge: { manga in
                        library.entry(for: manga).map { library.unreadCount(for: $0) } ?? 0
                    }
                ) {
                    EmptyView()
                }
                .searchable(text: $query, prompt: "Buscar en la biblioteca")
            }
        }
        .navigationTitle("Biblioteca")
        .navigationDestination(for: MangaItem.self) { manga in
            MangaDetailView(manga: manga)
        }
    }
}
