import SwiftUI

struct MangaDetailView: View {
    @State private var manga: MangaItem

    @EnvironmentObject private var extensions: ExtensionManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @State private var chapters: [ChapterItem] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var expanded = false
    @State private var reader: ReaderContext?
    @State private var newestFirst = true

    init(manga: MangaItem) {
        _manga = State(initialValue: manga)
    }

    private var installed: InstalledExtension? {
        extensions.extensionFor(sourceId: manga.sourceId)
    }

    /// Sources list chapters newest first, the same convention as Mihon.
    private var ascending: [ChapterItem] { Array(chapters.reversed()) }

    private var displayed: [ChapterItem] { newestFirst ? chapters : ascending }

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

            if let target = continueTarget {
                Button {
                    open(target)
                } label: {
                    Text(library.lastRead(in: manga) == nil ? "Empezar a leer" : "Continuar: \(target.name)")
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
                    Text("\(chapters.count) capítulos")
                    Spacer()
                    Button {
                        newestFirst.toggle()
                    } label: {
                        Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
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
                Button {
                    toggleLibrary()
                } label: {
                    Image(systemName: library.contains(manga) ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .refreshable { await refresh() }
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

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(manga: manga)
                .frame(width: 110, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.title3.bold())
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
            }
            Spacer(minLength: 0)
        }
    }

    private func chapterRow(_ chapter: ChapterItem) -> some View {
        let read = library.isRead(chapter, in: manga)
        return Button {
            open(chapter)
        } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(read ? "No leído" : "Leído") {
                library.setRead(!read, chapter: chapter, in: manga)
            }
            .tint(read ? .gray : .moka)
        }
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
        }
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
        } catch {
            self.error = error.localizedDescription
        }
    }
}
