import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var query = ""
    @State private var selectedCategory: String?
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var addingCategory = false
    @State private var newCategoryName = ""
    @State private var confirmingRemoval = false

    private var items: [LibraryEntry] {
        var all = library.sortedEntries.filter { ContentFilter.isAllowed($0.manga) }
        if let selectedCategory {
            all = all.filter { $0.categories?.contains(selectedCategory) == true }
        }
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
            } else {
                VStack(spacing: 0) {
                    if !library.categories.isEmpty {
                        categoryChips
                    }
                    if items.isEmpty {
                        EmptyStateView(
                            symbol: query.isEmpty ? "tray" : "magnifyingglass",
                            title: query.isEmpty ? "Nada por aquí" : "Sin resultados",
                            message: query.isEmpty
                                ? "Esta categoría todavía no tiene series."
                                : "Nada en tu biblioteca se llama “\(query)”."
                        )
                    } else {
                        MangaGrid(
                            items: items.map(\.manga),
                            badge: { manga in
                                library.entry(for: manga).map { library.unreadCount(for: $0) } ?? 0
                            },
                            selection: isSelecting ? selectionBinding : nil
                        ) {
                            EmptyView()
                        }
                    }
                }
                .searchable(text: $query, prompt: "Buscar en la biblioteca")
            }
        }
        .navigationTitle(isSelecting ? "\(selection.count) seleccionadas" : "Biblioteca")
        .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(selection.count == items.count ? "Ninguna" : "Todas") {
                        selection = selection.count == items.count
                            ? []
                            : Set(items.map(\.manga.id))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") { exitSelection() }
                        .font(.body.weight(.semibold))
                }
            } else {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !library.entries.isEmpty {
                        Button {
                            isSelecting = true
                        } label: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                    Menu {
                        Picker("Ordenar por", selection: $settings.librarySort) {
                            ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
        .navigationDestination(for: MangaItem.self) { manga in
            MangaDetailView(manga: manga)
        }
        .alert("Nueva categoría", isPresented: $addingCategory) {
            TextField("Nombre", text: $newCategoryName)
            Button("Cancelar", role: .cancel) {}
            Button("Crear") {
                if let category = library.addCategory(named: newCategoryName) {
                    if !selection.isEmpty {
                        library.toggleCategory(category.id, forEntries: Array(selection))
                    } else {
                        selectedCategory = category.id
                    }
                }
                newCategoryName = ""
            }
        } message: {
            Text("Por ejemplo: Favoritos, Al día, Pendientes…")
        }
        .confirmationDialog(
            selection.count == 1
                ? "¿Quitar 1 serie de la biblioteca?"
                : "¿Quitar \(selection.count) series de la biblioteca?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Quitar", role: .destructive) {
                library.removeEntries(ids: Array(selection))
                exitSelection()
            }
        }
    }

    // MARK: - Pieces

    private var selectionBinding: Binding<Set<String>> {
        Binding(get: { selection }, set: { selection = $0 })
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Todas", isOn: selectedCategory == nil) { selectedCategory = nil }
                ForEach(library.categories) { category in
                    chip(category.name, isOn: selectedCategory == category.id) {
                        selectedCategory = selectedCategory == category.id ? nil : category.id
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isOn ? Color.moka : Color(.secondarySystemBackground),
                    in: Capsule()
                )
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var selectionBar: some View {
        HStack(spacing: 4) {
            barButton("Leído", symbol: "checkmark.circle") {
                library.bulkSetRead(true, entryIds: Array(selection))
                exitSelection()
            }
            barButton("No leído", symbol: "circle") {
                library.bulkSetRead(false, entryIds: Array(selection))
                exitSelection()
            }
            categoriesMenu
            barButton("Quitar", symbol: "trash", role: .destructive) {
                confirmingRemoval = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .disabled(selection.isEmpty)
    }

    private var categoriesMenu: some View {
        Menu {
            ForEach(library.categories) { category in
                Button {
                    library.toggleCategory(category.id, forEntries: Array(selection))
                } label: {
                    let allIn = selection.allSatisfy { library.isInCategory($0, category.id) }
                    if allIn && !selection.isEmpty {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
            if !library.categories.isEmpty { Divider() }
            Button {
                newCategoryName = ""
                addingCategory = true
            } label: {
                Label("Nueva categoría…", systemImage: "plus")
            }
        } label: {
            barLabel("Categoría", symbol: "folder")
        }
    }

    private func barButton(
        _ title: String,
        symbol: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            barLabel(title, symbol: symbol)
        }
    }

    private func barLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.body)
            Text(title)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func exitSelection() {
        isSelecting = false
        selection = []
    }
}
