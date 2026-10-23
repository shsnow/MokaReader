import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @State private var confirmingDeleteAll = false

    private struct SeriesGroup: Identifiable {
        let mangaId: String
        let title: String
        let chapters: [(key: String, record: DownloadedChapter)]
        var id: String { mangaId }
        var bytes: Int64 { chapters.reduce(0) { $0 + $1.record.bytes } }
    }

    private var groups: [SeriesGroup] {
        Dictionary(grouping: downloads.downloaded.map { (key: $0.key, record: $0.value) }) { $0.record.mangaId }
            .map { mangaId, items in
                SeriesGroup(
                    mangaId: mangaId,
                    title: items.first?.record.mangaTitle ?? "",
                    chapters: items.sorted {
                        $0.record.chapterName.localizedStandardCompare($1.record.chapterName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        List {
            if !downloads.queue.isEmpty {
                Section {
                    ForEach(downloads.queue) { job in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.chapter.name)
                                Text(job.manga.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let value = downloads.progress[job.id] {
                                ProgressView(value: value)
                                    .frame(width: 70)
                            } else {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Cancelar", role: .destructive) { downloads.cancel(job) }
                        }
                    }
                } header: {
                    HStack {
                        Text("En cola (\(downloads.queue.count))")
                        Spacer()
                        Button("Cancelar todo") { downloads.cancelAll() }
                            .font(.caption)
                    }
                } footer: {
                    Text("Mantén Wizard Cat Reader abierto mientras descarga. Si sales de la app, la descarga sigue unos momentos y se retoma al volver.")
                }
            }

            if !downloads.failedJobs.isEmpty {
                Section("Con error") {
                    ForEach(downloads.failedJobs) { job in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.chapter.name)
                                Text(job.manga.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(downloads.failures[job.id] ?? "Error desconocido")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Reintentar") { downloads.retry(job) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                        .swipeActions {
                            Button("Descartar", role: .destructive) {
                                downloads.dismissFailure(job)
                            }
                        }
                    }
                }
            }

            if groups.isEmpty && downloads.queue.isEmpty && downloads.failedJobs.isEmpty {
                Section {
                    Text("No tienes capítulos descargados. Desde la ficha de una serie, toca el botón de descarga o desliza un capítulo hacia la derecha.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.chapters, id: \.key) { item in
                        HStack {
                            Text(item.record.chapterName)
                            Spacer()
                            Text("\(item.record.pageCount) págs · \(item.record.bytes.byteText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Borrar", role: .destructive) { downloads.delete(key: item.key) }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text(group.bytes.byteText)
                    }
                }
            }
        }
        .navigationTitle("Descargas")
        .toolbar {
            if !downloads.downloaded.isEmpty {
                Button("Borrar todo", role: .destructive) { confirmingDeleteAll = true }
            }
        }
        .confirmationDialog(
            "¿Borrar todas las descargas? (\(downloads.totalBytes.byteText))",
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Borrar todo", role: .destructive) { downloads.deleteAll() }
        }
    }
}
