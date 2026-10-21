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
    @EnvironmentObject private var downloads: DownloadManager

    @State private var chapterIndex: Int
    @State private var pages: [PageItem] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var mode: ReadingMode = .webtoon
    @State private var showOverlay = true
    @State private var currentPage = 0
    @State private var isOffline = false

    /// Webtoon zoom: the strip is laid out wider and scrolls in both directions.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var pan: CGFloat = 0
    @GestureState private var panDrag: CGFloat = 0

    /// How many pages ahead to load before they come on screen.
    private let prefetchCount = 4

    init(context: ReaderContext) {
        self.context = context
        _chapterIndex = State(initialValue: context.startIndex)
    }

    private var chapter: ChapterItem { context.chapters[chapterIndex] }
    private var hasNext: Bool { chapterIndex + 1 < context.chapters.count }
    private var hasPrevious: Bool { chapterIndex > 0 }

    private var background: Color { settings.readerBackground.color }
    private var isLightBackground: Bool { settings.readerBackground == .white }
    private var controlColor: Color { isLightBackground ? .black : .white }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background.ignoresSafeArea()

                if isLoading && pages.isEmpty {
                    ProgressView("Cargando capítulo…")
                        .tint(controlColor)
                        .foregroundStyle(controlColor)
                } else if let error, pages.isEmpty {
                    VStack(spacing: 14) {
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(controlColor)
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
        .onAppear {
            if settings.keepScreenAwake { UIApplication.shared.isIdleTimerDisabled = true }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Webtoon

    private func webtoon(width fullWidth: CGFloat) -> some View {
        // The side margin some long strips read better with.
        let width = fullWidth * (1 - 2 * settings.webtoonPadding)
        let decodeWidth = width * displayScale * 1.5
        let scale = min(max(zoom * pinch, 1), 3)
        // Horizontal room the zoomed strip has on each side.
        let maxPan = width * (scale - 1) / 2
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    ReaderPageView(
                        page: page,
                        manga: context.manga,
                        installed: context.installed,
                        width: width,
                        decodeWidth: decodeWidth,
                        fitHeight: nil,
                        onTap: nil
                    )
                    .onAppear {
                        currentPage = offset
                        prefetch(after: offset, decodeWidth: decodeWidth)
                        if offset == pages.count - 1 { markRead() }
                    }
                }
                chapterEnd
                    .frame(minHeight: 260)
            }
            .frame(maxWidth: .infinity)
        }
        .id(chapter.url)
        // Zoom scales the visible viewport around the screen centre; the strip keeps its layout,
        // so the reading position never moves and pages still load lazily.
        .scaleEffect(scale, anchor: .center)
        .offset(x: min(max(pan + panDrag, -maxPan), maxPan))
        .clipped()
        .simultaneousGesture(
            MagnificationGesture()
                .updating($pinch) { value, state, _ in state = value }
                .onEnded { value in
                    withAnimation(.easeOut(duration: 0.15)) {
                        zoom = min(max(zoom * value, 1), 3)
                        if zoom <= 1.01 { zoom = 1; pan = 0 }
                        let limit = width * (zoom - 1) / 2
                        pan = min(max(pan, -limit), limit)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .updating($panDrag) { value, state, _ in
                    if zoom > 1.01 { state = value.translation.width }
                }
                .onEnded { value in
                    guard zoom > 1.01 else { return }
                    let limit = width * (zoom - 1) / 2
                    pan = min(max(pan + value.translation.width, -limit), limit)
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.2)) {
                if zoom > 1.05 {
                    zoom = 1
                    pan = 0
                } else {
                    zoom = 2
                }
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
        }
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
                    decodeWidth: size.width * displayScale * 2,
                    fitHeight: size.height,
                    onTap: { position in handlePagedTap(position) }
                )
                .tag(offset)
            }
            chapterEnd
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() } }
                .tag(pages.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, mode == .rightToLeft ? .rightToLeft : .leftToRight)
        .id("\(chapter.url)-\(mode.rawValue)")
        .onChange(of: currentPage) { value in
            prefetch(after: value, decodeWidth: size.width * displayScale * 2)
            if value >= pages.count - 1 && !pages.isEmpty { markRead() }
        }
        .onAppear {
            prefetch(after: currentPage, decodeWidth: size.width * displayScale * 2)
        }
    }

    /// Edge taps turn pages; the middle of the screen shows or hides the controls.
    /// In right-to-left mode the left edge moves forward, like a printed manga.
    private func handlePagedTap(_ position: CGFloat) {
        guard settings.tapZonesEnabled else {
            withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            return
        }
        let forward: Bool
        if position < 0.3 {
            forward = mode == .rightToLeft
        } else if position > 0.7 {
            forward = mode != .rightToLeft
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            return
        }
        let target = currentPage + (forward ? 1 : -1)
        guard target >= 0, target <= pages.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) { currentPage = target }
    }

    private func prefetch(after index: Int, decodeWidth: CGFloat) {
        guard !pages.isEmpty else { return }
        let start = index + 1
        let end = min(index + prefetchCount, pages.count - 1)
        guard start <= end else { return }
        let upcoming = Array(pages[start...end])
        let manga = context.manga
        let installed = context.installed
        Task {
            await ImagePipeline.shared.prefetch(
                upcoming, sourceId: manga.sourceId, installed: installed, maxWidth: decodeWidth
            )
        }
    }

    // MARK: - Pieces

    private var chapterEnd: some View {
        VStack(spacing: 16) {
            Text("Terminaste \(chapter.name)")
                .font(.headline)
                .foregroundStyle(controlColor)
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
                    .foregroundStyle(controlColor.opacity(0.7))
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
                    HStack(spacing: 6) {
                        Text(chapter.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if isOffline {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                Spacer()
                if mode == .webtoon && zoom > 1.05 {
                    Button {
                        withAnimation { zoom = 1; pan = 0 }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                }
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
                let position = currentPage
                mode = value
                zoom = 1
                pan = 0
                // Keep the reading position across mode changes.
                currentPage = pages.isEmpty ? 0 : min(position, pages.count - 1)
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
        zoom = 1
        pan = 0
        defer { isLoading = false }
        let target = chapter
        library.markOpened(target, in: context.manga)

        // Downloaded chapters open from disk, without the network or the extension engine.
        if let local = downloads.localPages(manga: context.manga, chapter: target) {
            isOffline = true
            pages = local
            return
        }
        isOffline = false
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
        if settings.deleteAfterReading && isOffline {
            downloads.delete(manga: context.manga, chapter: chapter)
        }
    }
}

/// One page. Webtoon pages fill the width at their natural height; paged pages fit the screen
/// and can be zoomed.
struct ReaderPageView: View {
    let page: PageItem
    let manga: MangaItem
    let installed: InstalledExtension
    let width: CGFloat
    let decodeWidth: CGFloat
    let fitHeight: CGFloat?
    /// Paged mode only: horizontal tap position, 0 (left) to 1 (right).
    let onTap: ((CGFloat) -> Void)?

    @State private var image: UIImage?
    @State private var failed: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                if let fitHeight {
                    ZoomableImageView(image: image) { position in onTap?(position) }
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
                .foregroundStyle(.gray)
                .padding()
                .frame(width: width, height: fitHeight ?? width * 1.2)
            } else {
                ProgressView()
                    .tint(.gray)
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
