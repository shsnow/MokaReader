import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var query = ""

    private var items: [LibraryEntry] {
        var all = library.sortedEntries.filter { ContentFilter.isAllowed($0.manga) }
        switch settings.librarySort {
            case .recent:
                break
            case .title:
                all.sort {
                    $0.manga.title.localizedCaseInsensitiveCompare($1.manga.title) == .orderedAscending
                }
            case .unread:
                all.sort { library.unreadCount(for: $0) > library.unreadCount(for: $1) }
        }
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
            } else if items.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "Sin resultados",
                    message: "Nada en tu biblioteca se llama “\(query)”."
                )
                .searchable(text: $query, prompt: "Buscar en la biblioteca")
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
        .toolbar {
            Menu {
                Picker("Ordenar por", selection: $settings.librarySort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        .navigationDestination(for: MangaItem.self) { manga in
            MangaDetailView(manga: manga)
        }
    }
}
