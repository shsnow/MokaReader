import SwiftUI

@main
struct MokaReaderApp: App {
    @StateObject private var extensions = ExtensionManager.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var engine = EngineStatus.shared
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var updater = LibraryUpdater.shared

    init() {
        // MokaReader is a reading app; its titles are set in a book face.
        let large = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        if let serif = large.withDesign(.serif) {
            let bold = serif.withSymbolicTraits(.traitBold) ?? serif
            UINavigationBar.appearance().largeTitleTextAttributes = [
                .font: UIFont(descriptor: bold, size: 0)
            ]
        }
        let inline = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
        if let serifInline = inline.withDesign(.serif) {
            UINavigationBar.appearance().titleTextAttributes = [
                .font: UIFont(descriptor: serifInline, size: 0)
            ]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(extensions)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(downloads)
                .environmentObject(updater)
                .tint(.moka)
                .preferredColorScheme(settings.appTheme.colorScheme)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var extensions: ExtensionManager

    var body: some View {
        TabView {
            NavigationStack { LibraryView() }
                .tabItem { Label("Biblioteca", systemImage: "books.vertical") }
            NavigationStack { BrowseView() }
                .tabItem { Label("Explorar", systemImage: "safari") }
            NavigationStack { ActivityView() }
                .tabItem { Label("Actividad", systemImage: "bolt") }
            NavigationStack { ExtensionsView() }
                .tabItem { Label("Extensiones", systemImage: "puzzlepiece.extension") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
        .alert(
            "Algo salió mal",
            isPresented: Binding(
                get: { extensions.lastError != nil },
                set: { if !$0 { extensions.lastError = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(extensions.lastError ?? "") }
        )
    }
}
