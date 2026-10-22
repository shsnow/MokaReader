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

/// Signals from the tab bar: tapping a tab that is already selected triggers its shortcut.
@MainActor
final class TabShortcuts: ObservableObject {
    static let shared = TabShortcuts()
    /// Bumped when Actividad is tapped while already open; Actividad then shows the downloads.
    @Published var activityReselected = 0
    private init() {}
}

struct RootView: View {
    @EnvironmentObject private var extensions: ExtensionManager
    /// The app opens where it was left.
    @AppStorage("lastTab") private var selectedTab = 0

    /// Re-selecting the current tab reaches the setter with the same value.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { value in
                if value == 2 && selectedTab == 2 {
                    TabShortcuts.shared.activityReselected += 1
                }
                selectedTab = value
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack { LibraryView() }
                .tabItem { Label("Biblioteca", systemImage: "books.vertical") }
                .tag(0)
            NavigationStack { ActivityView() }
                .tabItem { Label("Actividad", systemImage: "bolt") }
                .tag(2)
            NavigationStack { BrowseView() }
                .tabItem { Label("Explorar", systemImage: "safari") }
                .tag(1)
            NavigationStack { ExtensionsView() }
                .tabItem { Label("Extensiones", systemImage: "puzzlepiece.extension") }
                .tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(4)
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
