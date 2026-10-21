import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// Used for manga that do not look like a long-strip format and have no per-series choice.
    @Published var defaultReadingMode: ReadingMode {
        didSet { defaults.set(defaultReadingMode.rawValue, forKey: "defaultReadingMode") }
    }

    @Published var showNSFW: Bool {
        didSet { defaults.set(showNSFW, forKey: "showNSFW") }
    }

    /// Source languages shown in Explorar. Empty means all.
    @Published var languages: Set<String> {
        didSet { defaults.set(Array(languages), forKey: "languages") }
    }

    private init() {
        // A local, so nothing reads `self` before every stored property is initialized.
        let defaults = UserDefaults.standard
        defaultReadingMode = ReadingMode(rawValue: defaults.string(forKey: "defaultReadingMode") ?? "")
            ?? .webtoon
        showNSFW = defaults.bool(forKey: "showNSFW")
        if let stored = defaults.array(forKey: "languages") as? [String] {
            languages = Set(stored)
        } else {
            languages = ["es", "es-419", "en", "all"]
        }
    }

    func shows(language: String) -> Bool {
        languages.isEmpty || languages.contains(language)
    }
}

extension Color {
    /// The terracotta of the app icon.
    static let moka = Color(red: 0.80, green: 0.33, blue: 0.18)
}
