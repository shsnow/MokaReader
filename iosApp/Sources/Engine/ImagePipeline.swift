import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Loads covers and chapter pages.
///
/// The fast path asks the extension only for the URL and headers (Referer, cookies, user agent)
/// and downloads with URLSession. If that fails or the bytes are not an image, it falls back to
/// letting the extension download the image itself, which runs the source's interceptors.
/// Downloaded chapters are read straight from disk.
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

    /// One load per page at a time, so the reader and the prefetcher never fetch the same page
    /// twice through the (serial) extension engine.
    private var inFlight: [String: Task<UIImage, Error>] = [:]

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

        // Imported series: the cover is a file next to the archives, never a download.
        if manga.isLocal {
            guard
                let data = LocalStore.coverData(for: manga),
                let image = Self.decode(data, maxWidth: maxWidth)
            else { throw URLError(.fileDoesNotExist) }
            store(image, for: key)
            return image
        }

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

    private static func key(for page: PageItem) -> String {
        if let localURL = page.localURL { return "local|\(localURL.path)" }
        return "page|\(page.imageURL ?? page.url)"
    }

    func page(_ page: PageItem, sourceId: Int64, installed: InstalledExtension, maxWidth: CGFloat) async throws -> UIImage {
        let key = Self.key(for: page)
        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let running = inFlight[key] { return try await running.value }

        let task = Task<UIImage, Error> {
            let data = try await self.pageData(page, sourceId: sourceId, installed: installed)
            guard let image = Self.decode(data, maxWidth: maxWidth) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let image = try await task.value
        store(image, for: key as NSString)
        return image
    }

    /// Loads the next pages into memory ahead of the reader. Errors are ignored: the page view
    /// retries on its own when it appears.
    func prefetch(_ pages: [PageItem], sourceId: Int64, installed: InstalledExtension, maxWidth: CGFloat) {
        for page in pages {
            let key = Self.key(for: page)
            if memory.object(forKey: key as NSString) != nil || inFlight[key] != nil { continue }
            Task { _ = try? await self.page(page, sourceId: sourceId, installed: installed, maxWidth: maxWidth) }
        }
    }

    /// The raw image bytes, used by the reader and by downloads.
    func pageData(_ page: PageItem, sourceId: Int64, installed: InstalledExtension) async throws -> Data {
        if let localURL = page.localURL {
            return try Data(contentsOf: localURL)
        }
        guard let imageURL = page.imageURL, !imageURL.isEmpty else { throw URLError(.badURL) }
        let pageURL = page.url.isEmpty ? imageURL : page.url
        do {
            let request = try await JVMEngine.shared.imageRequest(
                imageURL: imageURL, pageURL: pageURL, sourceId: sourceId, installed: installed
            )
            let downloaded = try await download(request)
            if Self.isImage(downloaded) { return downloaded }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Fall through to the extension's own client.
        }
        return try await JVMEngine.shared.materializeImage(
            imageURL: imageURL, pageURL: pageURL, sourceId: sourceId, installed: installed
        )
    }

    // MARK: - Maintenance

    func diskCacheBytes() -> Int64 {
        var total = Int64(session.configuration.urlCache?.currentDiskUsage ?? 0)
        if let files = try? FileManager.default.contentsOfDirectory(
            at: coverDirectory, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for file in files {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    func clearCaches() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
        try? FileManager.default.removeItem(at: coverDirectory)
        coverHeaders.removeAll()
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

    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetType(source) != nil
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Crops uniform borders (white margins, scan edges) around a page. The border color is
    /// whatever the corners agree on; if the content box is implausibly small, or the image has
    /// no real border, the original comes back untouched.
    static func trimmingBorders(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let fullWidth = cgImage.width
        let fullHeight = cgImage.height
        guard fullWidth > 16, fullHeight > 16 else { return image }

        // Analyze a small grayscale copy; precision at the pixel level is not needed.
        let sampleWidth = 96
        let sampleHeight = max(16, Int(Double(sampleWidth) * Double(fullHeight) / Double(fullWidth)))
        var samples = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)
        let drew = samples.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let space = CGColorSpace(name: CGColorSpace.linearGray),
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: sampleWidth,
                    height: sampleHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: sampleWidth,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else { return false }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }
        guard drew else { return image }

        func value(_ x: Int, _ y: Int) -> Int { Int(samples[y * sampleWidth + x]) }
        let background = (
            value(0, 0) + value(sampleWidth - 1, 0) +
            value(0, sampleHeight - 1) + value(sampleWidth - 1, sampleHeight - 1)
        ) / 4
        let threshold = 28

        var minX = sampleWidth, maxX = -1, minY = sampleHeight, maxY = -1
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth where abs(value(x, y) - background) > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }

        // One sample cell of breathing room, then scale back up to pixels.
        let scaleX = Double(fullWidth) / Double(sampleWidth)
        let scaleY = Double(fullHeight) / Double(sampleHeight)
        let crop = CGRect(
            x: max(0, (Double(minX) - 1) * scaleX),
            y: max(0, (Double(minY) - 1) * scaleY),
            width: min(Double(fullWidth), (Double(maxX - minX) + 3) * scaleX),
            height: min(Double(fullHeight), (Double(maxY - minY) + 3) * scaleY)
        ).intersection(CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight))

        let area = crop.width * crop.height
        let fullArea = CGFloat(fullWidth * fullHeight)
        // No meaningful border, or so aggressive it would eat the page: leave it alone.
        guard area < fullArea * 0.97, area > fullArea * 0.25 else { return image }
        guard let trimmed = cgImage.cropping(to: crop) else { return image }
        return UIImage(cgImage: trimmed, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Two pages side by side as one image, for the double-page spread. The pages are scaled
    /// to a common height; `rightToLeft` puts the first page on the right, like a printed manga.
    static func spread(_ first: UIImage, _ second: UIImage, rightToLeft: Bool) -> UIImage {
        let height = min(first.size.height, second.size.height)
        guard height > 0 else { return first }
        let firstWidth = first.size.width * (height / first.size.height)
        let secondWidth = second.size.width * (height / second.size.height)
        let size = CGSize(width: firstWidth + secondWidth, height: height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let leading = rightToLeft ? second : first
            let trailing = rightToLeft ? first : second
            let leadingWidth = rightToLeft ? secondWidth : firstWidth
            let trailingWidth = rightToLeft ? firstWidth : secondWidth
            leading.draw(in: CGRect(x: 0, y: 0, width: leadingWidth, height: height))
            trailing.draw(in: CGRect(x: leadingWidth, y: 0, width: trailingWidth, height: height))
        }
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
