import SwiftUI

struct MangaDetailView: View {
    @State private var manga: MangaItem

    @EnvironmentObject private var extensions: ExtensionManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadManager

    @State private var chapters: [ChapterItem] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var expanded = false
    @State private var reader: ReaderContext?
    @State private var newestFirst = true
    @State private var editingNote = false
    @State private var noteDraft = ""
    @State private var selectingChapters = false
    @State private var selectedChapters: Set<String> = []
    @State private var chapterQuery = ""
    @State private var siteURL: URL?

    init(manga: MangaItem) {
        _manga = State(initialValue: manga)
    }

    private var installed: InstalledExtension? {
        extensions.extensionFor(sourceId: manga.sourceId)
    }

    /// Sources list chapters newest first, the same convention as Mihon.
    private var ascending: [ChapterItem] { Array(chapters.reversed()) }

    private var displayed: [ChapterItem] {
        let ordered = newestFirst ? chapters : ascending
        let query = chapterQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return ordered }
        return ordered.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.number.map { number in String(format: "%g", number).contains(query) } == true
        }
    }

    private var unread: [ChapterItem] {
        ascending.filter { !library.isRead($0, in: manga) }
    }

    /// The selected chapters, oldest first, so batch downloads queue in reading order.
    private var selectedItems: [ChapterItem] {
        ascending.filter { selectedChapters.contains($0.url) }
    }

    private var continueTarget: ChapterItem? {
        let ordered = ascending
        guard !ordered.isEmpty else { return nil }
        if let last = library.lastRead(in: manga),
           let index = ordered.firstIndex(where: { $0.url == last }) {
            if library.isRead(ordered[index], in: manga), index + 1 < ordered.count {
                return ordered[index + 1]
            }
            return ordered[index]
        }
        return ordered.first { !library.isRead($0, in: manga) } ?? ordered.first
    }

    var body: some View {
        Group {
            if ContentFilter.isAllowed(manga) {
                content
            } else {
                EmptyStateView(
                    symbol: "hand.raised",
                    title: "Contenido no disponible",
                    message: "MokaReader es una app para toda la familia y no muestra contenido para adultos."
                )
            }
        }
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if chapters.isEmpty, let entry = library.entry(for: manga) {
                manga = entry.manga
                chapters = entry.chapters
            }
            await refresh()
        }
        .fullScreenCover(item: $reader) { context in
            ReaderView(context: context)
        }
    }

    private var content: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

            if let summary = manga.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 4)
                    Button(expanded ? "Ver menos" : "Ver más") {
                        withAnimation { expanded.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .listRowSeparator(.hidden)
            }

            if !manga.genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(manga.genres, id: \.self) { genre in
                            Text(genre)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            if library.contains(manga), !library.note(for: manga).isEmpty {
                Text(library.note(for: manga))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.moka.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .listRowSeparator(.hidden)
            }

            if let target = continueTarget {
                Button {
                    open(target)
                } label: {
                    Text(buttonTitle(for: target))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.moka, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }

            Section {
                if chapters.isEmpty && isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if chapters.isEmpty, let error {
                    VStack(spacing: 8) {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await refresh() } }
                    }
                    .frame(maxWidth: .infinity)
                }
                ForEach(displayed) { chapter in
                    chapterRow(chapter)
                }
            } header: {
                HStack {
                    if selectingChapters {
                        Text("\(selectedChapters.count) seleccionados")
                        Spacer()
                        Button(selectedChapters.count == chapters.count ? "Ninguno" : "Todos") {
                            selectedChapters = selectedChapters.count == chapters.count
                                ? []
                                : Set(chapters.map(\.url))
                        }
                        Button("Listo") {
                            selectingChapters = false
                            selectedChapters = []
                        }
                        .fontWeight(.semibold)
                    } else {
                        Text(chapters.count == 1 ? "1 capítulo" : "\(chapters.count) capítulos")
                        Spacer()
                        Button {
                            newestFirst.toggle()
                        } label: {
                            Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Modo de lectura", selection: modeBinding) {
                        ForEach(ReadingMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: modeBinding.wrappedValue.symbol)
                }
                downloadMenu
                if library.contains(manga) {
                    Button {
                        noteDraft = library.note(for: manga)
                        editingNote = true
                    } label: {
                        Image(systemName: library.note(for: manga).isEmpty ? "note.text" : "note.text.badge.plus")
                    }
                }
                Button {
                    toggleLibrary()
                } label: {
                    Image(systemName: library.contains(manga) ? "bookmark.fill" : "bookmark")
                }
                if let siteURL {
                    Menu {
                        Link(destination: siteURL) {
                            Label("Abrir en el sitio", systemImage: "safari")
                        }
                        ShareLink(item: siteURL) {
                            Label("Compartir enlace", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .refreshable { await refresh() }
        .searchable(
            text: $chapterQuery,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Buscar capítulo"
        )
        .safeAreaInset(edge: .bottom) {
            if selectingChapters {
                chapterSelectionBar
            }
        }
        .sheet(isPresented: $editingNote) {
            NavigationStack {
                TextEditor(text: $noteDraft)
                    .padding(12)
                    .navigationTitle("Nota")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { editingNote = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Guardar") {
                                library.setNote(noteDraft, for: manga)
                                editingNote = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private var downloadMenu: some View {
        Menu {
            Button {
                download(Array(unread.prefix(5)))
            } label: {
                Label("Siguientes 5 sin leer", systemImage: "arrow.down.circle")
            }
            Button {
                download(unread)
            } label: {
                Label("Todos los sin leer (\(unread.count))", systemImage: "arrow.down.circle")
            }
            Button {
                download(ascending)
            } label: {
                Label("Todos los capítulos", systemImage: "arrow.down.to.line")
            }
            Divider()
            Button {
                selectingChapters = true
            } label: {
                Label("Seleccionar capítulos", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                downloads.deleteAll(mangaId: manga.id)
            } label: {
                Label("Borrar descargas de esta serie", systemImage: "trash")
            }
        } label: {
            Image(systemName: "arrow.down.circle")
        }
        .disabled(chapters.isEmpty || installed == nil)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(manga: manga)
                .frame(width: 110, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                )
            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.system(.title3, design: .serif).bold())
                    .lineLimit(4)
                if let author = manga.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let status = manga.statusText {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
                if let source = extensions.source(id: manga.sourceId) {
                    Text("\(source.name) · \(Language.displayName(source.lang))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let time = library.readingTimeText(for: manga) {
                    Label(time, systemImage: "book")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chapterRow(_ chapter: ChapterItem) -> some View {
        let read = library.isRead(chapter, in: manga)
        let state = downloads.state(manga: manga, chapter: chapter)
        let isSelected = selectedChapters.contains(chapter.url)
        return Button {
            if selectingChapters {
                if isSelected {
                    selectedChapters.remove(chapter.url)
                } else {
                    selectedChapters.insert(chapter.url)
                }
            } else {
                open(chapter)
            }
        } label: {
            HStack(spacing: 10) {
                if selectingChapters {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.moka : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.name)
                        .font(.subheadline.weight(read ? .regular : .medium))
                        .foregroundStyle(read ? .secondary : .primary)
                    HStack(spacing: 6) {
                        if let date = chapter.date { Text(date.shortText) }
                        if let scanlator = chapter.scanlator, !scanlator.isEmpty { Text("· \(scanlator)") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if state == .none, !selectingChapters, installed != nil {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .onTapGesture { download([chapter]) }
                } else {
                    downloadIndicator(state)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if !selectingChapters {
                Button(read ? "No leído" : "Leído") {
                    library.setRead(!read, chapter: chapter, in: manga)
                }
                .tint(read ? .gray : .moka)
            }
        }
        .swipeActions(edge: .leading) {
            if !selectingChapters {
                if state == .downloaded {
                    Button("Borrar", role: .destructive) {
                        downloads.delete(manga: manga, chapter: chapter)
                    }
                } else {
                    Button("Descargar") {
                        download([chapter])
                    }
                    .tint(.blue)
                }
            }
        }
    }

    private var chapterSelectionBar: some View {
        HStack(spacing: 4) {
            selectionBarButton("Descargar", symbol: "arrow.down.circle") {
                download(selectedItems.filter { !downloads.isDownloaded(manga: manga, chapter: $0) })
            }
            selectionBarButton("Leído", symbol: "checkmark.circle") {
                library.setRead(true, chapterURLs: selectedItems.map(\.url), in: manga)
            }
            selectionBarButton("No leído", symbol: "circle") {
                library.setRead(false, chapterURLs: selectedItems.map(\.url), in: manga)
            }
            selectionBarButton("Borrar desc.", symbol: "trash", role: .destructive) {
                for chapter in selectedItems {
                    downloads.delete(manga: manga, chapter: chapter)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .disabled(selectedChapters.isEmpty)
    }

    private func selectionBarButton(
        _ title: String,
        symbol: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
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
    }

    @ViewBuilder
    private func downloadIndicator(_ state: DownloadState) -> some View {
        switch state {
            case .none:
                EmptyView()
            case .queued:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            case .downloading(let value):
                Text("\(Int(value * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.moka)
            case .downloaded:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
        }
    }

    private func buttonTitle(for target: ChapterItem) -> String {
        if library.lastRead(in: manga) == nil { return "Empezar a leer" }
        if unread.isEmpty { return "Releer: \(target.name)" }
        return "Continuar: \(target.name)"
    }

    private var modeBinding: Binding<ReadingMode> {
        Binding(
            get: { library.readingMode(for: manga, fallback: settings.defaultReadingMode) },
            set: { library.setReadingMode($0, for: manga) }
        )
    }

    private func toggleLibrary() {
        if library.contains(manga) {
            library.remove(manga)
        } else {
            library.add(manga, chapters: chapters)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func download(_ items: [ChapterItem]) {
        guard let installed, !items.isEmpty else { return }
        downloads.enqueue(items, manga: manga, installed: installed)
    }

    private func open(_ chapter: ChapterItem) {
        guard let installed else {
            error = "La extensión de esta fuente no está instalada."
            return
        }
        let ordered = ascending
        guard let index = ordered.firstIndex(of: chapter) else { return }
        reader = ReaderContext(manga: manga, installed: installed, chapters: ordered, startIndex: index)
    }

    private func refresh() async {
        guard let installed else {
            error = "Instala la extensión de esta fuente para ver sus capítulos."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await JVMEngine.shared.details(of: manga, installed: installed)
            manga = result.manga
            chapters = result.chapters
            error = nil
            library.refresh(result.manga, chapters: result.chapters)
            if siteURL == nil {
                siteURL = try? await JVMEngine.shared.siteURL(of: manga, installed: installed)
            }
        } catch {
            // Offline with a saved copy: keep showing it instead of an error.
            if chapters.isEmpty { self.error = error.localizedDescription }
        }
    }
}
