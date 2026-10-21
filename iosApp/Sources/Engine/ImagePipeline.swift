import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Loads covers and chapter pages.
///
/// The fast path asks the extension only for the URL and headers (Referer, cookies, user agent)
/// and downloads with URLSession. If that fails or the bytes are not an image, it falls back to
/// letting the extension download the image itself, which runs the source's interceptors.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 220 * 1024 * 1024
        return cache
    }()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024
        )
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    /// Cover headers are the source's plain headers, the same for every cover of that source.
    private var coverHeaders: [Int64: (headers: [String: String], expires: Date)] = [:]

    private var coverDirectory: URL {
        let url = Storage.cacheDirectory.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Covers

    func cover(for manga: MangaItem, installed: InstalledExtension?, maxWidth: CGFloat) async throws -> UIImage {
        guard let address = manga.thumbnailURL, !address.isEmpty else { throw URLError(.badURL) }
        let key = "cover|\(address)" as NSString
        if let cached = memory.object(forKey: key) { return cached }

        let file = coverDirectory.appendingPathComponent(Self.hash(address))
        if let data = try? Data(contentsOf: file), let image = Self.decode(data, maxWidth: maxWidth) {
            store(image, for: key)
            return image
        }

        let data: Data
        if let installed {
            data = try await fetchCover(address, sourceId: manga.sourceId, installed: installed)
        } else {
            guard let url = URL(string: address) else { throw URLError(.badURL) }
            data = try await download(URLRequest(url: url))
        }
        guard let image = Self.decode(data, maxWidth: maxWidth) else { throw URLError(.cannotDecodeContentData) }
        try? data.write(to: file, options: .atomic)
        store(image, for: key)
        return image
    }

    private func fetchCover(_ address: String, sourceId: Int64, installed: InstalledExtension) async throws -> Data {
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        do {
            var request = URLRequest(url: url)
            for (name, value) in try await headersForCovers(sourceId: sourceId, sample: address, installed: installed) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            let data = try await download(request)
            if Self.isImage(data) { return data }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Fall through to the extension's own client.
        }
        return try await JVMEngine.shared.materializeImage(
            imageURL: address, pageURL: nil, sourceId: sourceId, installed: installed
        )
    }

    private func headersForCovers(sourceId: Int64, sample: String, installed: InstalledExtension) async throws -> [String: String] {
        if let cached = coverHeaders[sourceId], cached.expires > Date() { return cached.headers }
        let request = try await JVMEngine.shared.imageRequest(
            imageURL: sample, pageURL: nil, sourceId: sourceId, installed: installed
        )
        let headers = request.allHTTPHeaderFields ?? [:]
        coverHeaders[sourceId] = (headers, Date().addingTimeInterval(600))
        return headers
    }

    // MARK: - Pages

    func page(_ page: PageItem, sourceId: Int64, installed: InstalledExtension, maxWidth: CGFloat) async throws -> UIImage {
        guard let imageURL = page.imageURL, !imageURL.isEmpty else { throw URLError(.badURL) }
        let key = "page|\(imageURL)" as NSString
        if let cached = memory.object(forKey: key) { return cached }

        let pageURL = page.url.isEmpty ? imageURL : page.url
        var data: Data?
        do {
            let request = try await JVMEngine.shared.imageRequest(
                imageURL: imageURL, pageURL: pageURL, sourceId: sourceId, installed: installed
            )
            let downloaded = try await download(request)
            if Self.isImage(downloaded) { data = downloaded }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            data = nil
        }
        let bytes: Data
        if let data {
            bytes = data
        } else {
            bytes = try await JVMEngine.shared.materializeImage(
                imageURL: imageURL, pageURL: pageURL, sourceId: sourceId, installed: installed
            )
        }
        guard let image = Self.decode(bytes, maxWidth: maxWidth) else { throw URLError(.cannotDecodeContentData) }
        store(image, for: key)
        return image
    }

    // MARK: - Helpers

    private func download(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func store(_ image: UIImage, for key: NSString) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key, cost: cost)
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetType(source) != nil
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes at most `maxWidth` pixels wide. A webtoon page can be 800×12000 px; decoding it at
    /// full size for every page is what gets a reader killed for memory.
    static func decode(_ data: Data, maxWidth: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width > 0, height > 0
        else {
            return UIImage(data: data)
        }
        let limit = Double(maxWidth)
        let scale = width > limit ? limit / width : 1
        let maxPixelSize = max(width, height) * scale
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: image)
    }
}
