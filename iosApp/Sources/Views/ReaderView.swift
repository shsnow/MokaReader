import SwiftUI

struct ReaderContext: Identifiable {
    let id = UUID()
    let manga: MangaItem
    let installed: InstalledExtension
    /// Oldest first, so "next chapter" is index + 1.
    let chapters: [ChapterItem]
    let startIndex: Int
}

struct ReaderView: View {
    let context: ReaderContext

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @State private var chapterIndex: Int
    @State private var pages: [PageItem] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var mode: ReadingMode = .webtoon
    @State private var showOverlay = true
    @State private var currentPage = 0

    init(context: ReaderContext) {
        self.context = context
        _chapterIndex = State(initialValue: context.startIndex)
    }

    private var chapter: ChapterItem { context.chapters[chapterIndex] }
    private var hasNext: Bool { chapterIndex + 1 < context.chapters.count }
    private var hasPrevious: Bool { chapterIndex > 0 }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading && pages.isEmpty {
                    ProgressView("Cargando capítulo…")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else if let error, pages.isEmpty {
                    VStack(spacing: 14) {
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Button("Reintentar") { Task { await loadChapter() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(32)
                } else if mode == .webtoon {
                    webtoon(width: geometry.size.width)
                } else {
                    paged(size: geometry.size)
                }

                if showOverlay {
                    overlay
                }
            }
        }
        .statusBarHidden(!showOverlay)
        .task {
            mode = library.readingMode(for: context.manga, fallback: settings.defaultReadingMode)
            await loadChapter()
        }
    }

    // MARK: - Webtoon

    private func webtoon(width: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    ReaderPageView(
                        page: page,
                        manga: context.manga,
                        installed: context.installed,
                        width: width,
                        decodeWidth: width * displayScale,
                        fitHeight: nil
                    )
                    .onAppear {
                        currentPage = offset
                        if offset == pages.count - 1 { markRead() }
                    }
                }
                chapterEnd
                    .frame(minHeight: 260)
            }
        }
        .id(chapter.url)
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() } }
    }

    // MARK: - Paged

    private func paged(size: CGSize) -> some View {
        TabView(selection: $currentPage) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                ReaderPageView(
                    page: page,
                    manga: context.manga,
                    installed: context.installed,
                    width: size.width,
                    decodeWidth: size.width * displayScale * 1.5,
                    fitHeight: size.height
                )
                .tag(offset)
            }
            chapterEnd
                .tag(pages.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, mode == .rightToLeft ? .rightToLeft : .leftToRight)
        .id("\(chapter.url)-\(mode.rawValue)")
        .onChange(of: currentPage) { value in
            if value >= pages.count - 1 && !pages.isEmpty { markRead() }
        }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() } }
    }

    // MARK: - Pieces

    private var chapterEnd: some View {
        VStack(spacing: 16) {
            Text("Terminaste \(chapter.name)")
                .font(.headline)
                .foregroundStyle(.white)
            if hasNext {
                Button {
                    Task { await go(to: chapterIndex + 1) }
                } label: {
                    Label("Siguiente: \(context.chapters[chapterIndex + 1].name)", systemImage: "forward.end")
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No hay más capítulos por ahora.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var overlay: some View {
        VStack {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.manga.title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Text(chapter.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(.black.opacity(0.75))

            Spacer()

            HStack(spacing: 18) {
                Button {
                    Task { await go(to: chapterIndex - 1) }
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .disabled(!hasPrevious)

                Spacer()

                if !pages.isEmpty {
                    Text("\(min(currentPage + 1, pages.count)) / \(pages.count)")
                        .font(.footnote.monospacedDigit())
                }

                Spacer()

                Menu {
                    Picker("Modo de lectura", selection: modeBinding) {
                        ForEach(ReadingMode.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                } label: {
                    Image(systemName: mode.symbol)
                }

                Button {
                    Task { await go(to: chapterIndex + 1) }
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(!hasNext)
            }
            .font(.title3)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(.black.opacity(0.75))
        }
        .transition(.opacity)
    }

    private var modeBinding: Binding<ReadingMode> {
        Binding(
            get: { mode },
            set: { value in
                mode = value
                currentPage = 0
                library.setReadingMode(value, for: context.manga)
            }
        )
    }

    // MARK: - Loading

    private func go(to index: Int) async {
        guard context.chapters.indices.contains(index) else { return }
        chapterIndex = index
        await loadChapter()
    }

    private func loadChapter() async {
        isLoading = true
        error = nil
        pages = []
        currentPage = 0
        defer { isLoading = false }
        let target = chapter
        library.markOpened(target, in: context.manga)
        do {
            let loaded = try await JVMEngine.shared.pages(
                of: target, manga: context.manga, installed: context.installed
            )
            guard target == chapter else { return }
            if loaded.isEmpty {
                error = "Este capítulo no tiene páginas."
            }
            pages = loaded
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func markRead() {
        library.setRead(true, chapter: chapter, in: context.manga)
    }
}

/// One page. Webtoon pages fill the width at their natural height; paged pages fit the screen.
struct ReaderPageView: View {
    let page: PageItem
    let manga: MangaItem
    let installed: InstalledExtension
    let width: CGFloat
    let decodeWidth: CGFloat
    let fitHeight: CGFloat?

    @State private var image: UIImage?
    @State private var failed: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                if let fitHeight {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width, height: fitHeight)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(image.size, contentMode: .fit)
                        .frame(width: width)
                }
            } else if let failed {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Página \(page.index + 1): \(failed)")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Reintentar") { attempt += 1 }
                        .buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
                .padding()
                .frame(width: width, height: fitHeight ?? width * 1.2)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(width: width, height: fitHeight ?? width * 1.4)
            }
        }
        .task(id: attempt) {
            guard image == nil else { return }
            failed = nil
            do {
                image = try await ImagePipeline.shared.page(
                    page,
                    sourceId: manga.sourceId,
                    installed: installed,
                    maxWidth: decodeWidth
                )
            } catch {
                if !Task.isCancelled { failed = error.localizedDescription }
            }
        }
    }
}
