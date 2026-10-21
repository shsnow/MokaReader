import SwiftUI

@main
struct MokaReaderApp: App {
    @StateObject private var extensions = ExtensionManager.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var engine = EngineStatus.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(extensions)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(engine)
                .tint(.moka)
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
