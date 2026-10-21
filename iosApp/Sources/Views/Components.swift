import SwiftUI

/// A manga cover loaded through the source's own headers.
struct CoverImage: View {
    let manga: MangaItem
    @EnvironmentObject private var extensions: ExtensionManager
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: manga.thumbnailURL) {
                image = nil
                failed = false
                let installed = extensions.extensionFor(sourceId: manga.sourceId)
                do {
                    image = try await ImagePipeline.shared.cover(
                        for: manga,
                        installed: installed,
                        maxWidth: 360
                    )
                } catch {
                    if !Task.isCancelled { failed = true }
                }
            }
    }
}

struct MangaCell: View {
    let manga: MangaItem
    var badge: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(manga: manga)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                )
                .overlay(alignment: .topLeading) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.moka, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
            Text(manga.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }
}

struct MangaGrid<Footer: View>: View {
    let items: [MangaItem]
    var badge: (MangaItem) -> Int = { _ in 0 }
    var onItemAppear: (MangaItem) -> Void = { _ in }
    @ViewBuilder var footer: () -> Footer

    @EnvironmentObject private var settings: AppSettings

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: settings.gridColumns)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { manga in
                    NavigationLink(value: manga) {
                        MangaCell(manga: manga, badge: badge(manga))
                    }
                    .buttonStyle(.plain)
                    .onAppear { onItemAppear(manga) }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            footer()
                .padding(.vertical, 24)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.moka)
                .frame(width: 76, height: 76)
                .background(Color.moka.opacity(0.12), in: Circle())
            Text(title)
                .font(.system(.title3, design: .serif).weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExtensionIcon: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(.secondary)
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The engine state as a single row, used where a screen depends on the JVM.
struct EngineBanner: View {
    @EnvironmentObject private var engine: EngineStatus

    var body: some View {
        switch engine.state {
            case .starting:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Iniciando el motor de extensiones…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
            case .failed(let message):
                Text("El motor no pudo iniciar: \(message)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(10)
            default:
                EmptyView()
        }
    }
}

extension Date {
    var shortText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
