import SwiftUI

struct BrowseView: View {
    @EnvironmentObject private var extensions: ExtensionManager
    @EnvironmentObject private var settings: AppSettings

    private var visibleSources: [SourceInfo] {
        extensions.installed
            .filter { !$0.nsfw }
            .flatMap(\.sources)
            .filter { settings.shows(language: $0.lang) }
    }

    private struct SourceGroup: Identifiable {
        let lang: String
        let sources: [SourceInfo]
        var id: String { lang }
    }

    private var groups: [SourceGroup] {
        Dictionary(grouping: visibleSources) { $0.lang }
            .map { SourceGroup(lang: $0.key, sources: $0.value.sorted { $0.name < $1.name }) }
            .sorted { Language.displayName($0.lang) < Language.displayName($1.lang) }
    }

    var body: some View {
        Group {
            if extensions.installed.isEmpty {
                EmptyStateView(
                    symbol: "puzzlepiece.extension",
                    title: "No hay fuentes",
                    message: "Agrega un repositorio en la pestaña Extensiones e instala alguna."
                )
            } else if visibleSources.isEmpty {
                EmptyStateView(
                    symbol: "globe",
                    title: "Ninguna fuente en tus idiomas",
                    message: "Cambia los idiomas visibles en Ajustes."
                )
            } else {
                List {
                    ForEach(groups) { group in
                        Section(Language.displayName(group.lang)) {
                            ForEach(group.sources) { source in
                                NavigationLink(value: SourceRef(source: source)) {
                                    HStack(spacing: 12) {
                                        ExtensionIcon(url: extensions.extensionFor(sourceId: source.id)?.iconURL)
                                        Text(source.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Explorar")
        .navigationDestination(for: SourceRef.self) { ref in
            SourceBrowseView(source: ref.source)
        }
        .navigationDestination(for: MangaItem.self) { manga in
            MangaDetailView(manga: manga)
        }
    }
}

struct SourceBrowseView: View {
    let source: SourceInfo

    @EnvironmentObject private var extensions: ExtensionManager
    @State private var mode: Mode = .popular
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var items: [MangaItem] = []
    @State private var page = 0
    @State private var hasNextPage = true
    @State private var isLoading = false
    @State private var error: String?

    enum Mode: String, CaseIterable, Identifiable {
        case popular = "Popular"
        case latest = "Recientes"
        var id: String { rawValue }
    }

    private var listing: JVMEngine.Listing {
        if !submittedQuery.isEmpty { return .search(submittedQuery) }
        return mode == .popular ? .popular : .latest
    }

    var body: some View {
        VStack(spacing: 0) {
            EngineBanner()
            if source.supportsLatest && submittedQuery.isEmpty {
                Picker("Lista", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            if let error, items.isEmpty {
                EmptyStateView(symbol: "exclamationmark.triangle", title: "No se pudo cargar", message: error)
                Button("Reintentar") { Task { await reload() } }
                    .padding(.bottom, 40)
            } else if items.isEmpty && isLoading {
                ProgressView("Cargando…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MangaGrid(
                    items: items,
                    onItemAppear: { manga in
                        if manga.id == items.last?.id { Task { await loadNextPage() } }
                    }
                ) {
                    if isLoading {
                        ProgressView()
                    } else if let error {
                        Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    }
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Buscar en \(source.name)")
        .onSubmit(of: .search) {
            submittedQuery = query.trimmingCharacters(in: .whitespaces)
            Task { await reload() }
        }
        .onChange(of: query) { value in
            if value.isEmpty && !submittedQuery.isEmpty {
                submittedQuery = ""
                Task { await reload() }
            }
        }
        .onChange(of: mode) { _ in Task { await reload() } }
        .task { if items.isEmpty { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        items = []
        page = 0
        hasNextPage = true
        error = nil
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoading, hasNextPage else { return }
        guard let installed = extensions.extensionFor(sourceId: source.id) else {
            error = "La extensión de esta fuente ya no está instalada."
            return
        }
        isLoading = true
        defer { isLoading = false }
        let requested = listing
        do {
            // A page can come back empty after hiding adult series; fetch a few more pages so
            // the infinite scroll does not stall with nothing on screen to trigger it.
            var attempts = 0
            repeat {
                let result = try await JVMEngine.shared.mangaPage(
                    requested, source: source, installed: installed, page: page + 1
                )
                guard requested == listing else { return }
                let known = Set(items.map(\.id))
                let fresh = ContentFilter.allowed(result.items).filter { !known.contains($0.id) }
                items.append(contentsOf: fresh)
                page += 1
                hasNextPage = result.hasNextPage && !result.items.isEmpty
                attempts += 1
                if !fresh.isEmpty { break }
            } while hasNextPage && attempts < 4
            error = nil
        } catch {
            self.error = error.localizedDescription
            hasNextPage = false
        }
    }
}
