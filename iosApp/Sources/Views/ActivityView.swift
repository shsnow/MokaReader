import SwiftUI

/// Novedades (new chapters across the library) and Historial (what was read, newest first).
struct ActivityView: View {
    enum Section: String, CaseIterable, Identifiable {
        case updates = "Novedades"
        case history = "Historial"
        var id: String { rawValue }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var extensions: ExtensionManager
    @EnvironmentObject private var updater: LibraryUpdater
    @ObservedObject private var shortcuts = TabShortcuts.shared
    @State private var section: Section = .updates
    @State private var showingDownloads = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch section {
                case .updates: UpdatesList()
                case .history: HistoryList()
            }
        }
        .navigationTitle("Actividad")
        .navigationDestination(for: MangaItem.self) { manga in
            MangaDetailView(manga: manga)
        }
        // Tapping Actividad again in the tab bar jumps to the downloads in progress.
        .navigationDestination(isPresented: $showingDownloads) {
            DownloadsView()
        }
        .onChange(of: shortcuts.activityReselected) { _ in
            showingDownloads = true
        }
        .toolbar {
            if section == .updates {
                if updater.isRefreshing {
                    Button("Detener") { updater.cancel() }
                } else {
                    Button {
                        updater.refreshAll(library: library, extensions: extensions)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(library.entries.isEmpty)
                }
            } else if !library.history.isEmpty {
                Button("Borrar") { library.clearHistory() }
            }
        }
    }
}

private struct UpdatesList: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var extensions: ExtensionManager
    @EnvironmentObject private var updater: LibraryUpdater

    var body: some View {
        List {
            if updater.isRefreshing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Actualizando \(updater.completed + 1) de \(updater.total)…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            } else if let finished = updater.lastFinished {
                Text(
                    updater.newChapters == 0
                        ? "Sin capítulos nuevos (\(finished.shortText))."
                        : "\(updater.newChapters) capítulos nuevos."
                )
                .font(.footnote)
                .foregroundStyle(updater.newChapters == 0 ? .secondary : Color.moka)
                .listRowSeparator(.hidden)
            }

            if library.entries.isEmpty {
                Text("Guarda series en tu biblioteca para ver aquí sus capítulos nuevos.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.latestUploads, id: \.chapter.url) { item in
                    NavigationLink(value: item.manga) {
                        row(item.manga, item.chapter)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await updater.refresh(library: library, extensions: extensions)
        }
    }

    private func row(_ manga: MangaItem, _ chapter: ChapterItem) -> some View {
        let read = library.isRead(chapter, in: manga)
        return HStack(spacing: 12) {
            CoverImage(manga: manga)
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(manga.title)
                    .font(.subheadline.weight(read ? .regular : .semibold))
                    .foregroundStyle(read ? .secondary : .primary)
                    .lineLimit(1)
                Text(chapter.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let date = chapter.date {
                    Text(date.shortText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if updater.lastNewURLs.contains(chapter.url) {
                    Text("Nuevo")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.moka.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.moka)
                } else if !read {
                    Circle()
                        .fill(Color.moka)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}

private struct HistoryList: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""

    private struct Day: Identifiable {
        let date: Date
        let records: [ReadingRecord]
        var id: Date { date }
    }

    private var filtered: [ReadingRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return library.history }
        return library.history.filter {
            $0.manga.title.localizedCaseInsensitiveContains(trimmed)
                || $0.chapterName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        return Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
            .map { Day(date: $0.key, records: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if library.history.isEmpty {
                EmptyStateView(
                    symbol: "clock",
                    title: "Sin historial",
                    message: "Los capítulos que abras van a aparecer aquí."
                )
            } else {
                List {
                    ForEach(days) { day in
                        SwiftUI.Section(day.date.shortText) {
                            ForEach(day.records) { record in
                                NavigationLink(value: record.manga) {
                                    HStack(spacing: 12) {
                                        CoverImage(manga: record.manga)
                                            .frame(width: 40, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(record.manga.title)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(1)
                                            Text(record.chapterName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Text(record.date, style: .time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions {
                                    Button("Borrar", role: .destructive) {
                                        library.deleteHistoryRecord(record)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Buscar en el historial")
            }
        }
    }
}
