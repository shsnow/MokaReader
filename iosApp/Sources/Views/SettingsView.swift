import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var extensions: ExtensionManager
    @EnvironmentObject private var engine: EngineStatus
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var library: LibraryStore

    @State private var showingImporter = false
    @State private var importing = false
    @State private var importSummary: MihonImportSummary?
    @State private var importError: String?
    @State private var exportDocument: TachibkDocument?
    @State private var exportError: String?
    @State private var cacheBytes: Int64 = 0
    @State private var clearingCookies = false
    @State private var cookiesResult: String?

    private let commonLanguages = ["all", "es", "es-419", "en", "pt-BR", "fr", "it", "de", "ja", "ko", "zh"]

    private var languageOptions: [String] {
        var seen = Set<String>()
        let fromSources = extensions.allSources.map(\.lang) + extensions.catalog.flatMap(\.languages)
        return (commonLanguages + fromSources.sorted()).filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section {
                Picker("Modo por defecto", selection: $settings.defaultReadingMode) {
                    ForEach(ReadingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Fondo del lector", selection: $settings.readerBackground) {
                    ForEach(ReaderBackground.allCases) { Text($0.title).tag($0) }
                }
                Picker("Margen lateral en webtoon", selection: $settings.webtoonPadding) {
                    Text("Sin margen").tag(0.0)
                    Text("Pequeño").tag(0.04)
                    Text("Mediano").tag(0.08)
                }
                Toggle("Zonas de toque para pasar página", isOn: $settings.tapZonesEnabled)
                Toggle("Mantener la pantalla encendida", isOn: $settings.keepScreenAwake)
                NavigationLink("Estadísticas de lectura") { InsightsView() }
            } header: {
                Text("Lectura")
            } footer: {
                Text("Manhwa, manhua y webtoons se abren en modo vertical. Puedes cambiar el modo de cada serie desde su ficha o dentro del lector.")
            }

            Section("Biblioteca") {
                Picker("Series por fila", selection: $settings.gridColumns) {
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented)
                NavigationLink {
                    CategoriesView()
                } label: {
                    HStack {
                        Text("Categorías")
                        Spacer()
                        Text(library.categories.isEmpty ? "Ninguna" : "\(library.categories.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Apariencia") {
                Picker("Tema", selection: $settings.appTheme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Contenido") {
                NavigationLink {
                    LanguagePicker(options: languageOptions)
                } label: {
                    HStack {
                        Text("Idiomas")
                        Spacer()
                        Text(settings.languages.isEmpty ? "Todos" : "\(settings.languages.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Descargas") {
                NavigationLink {
                    DownloadsView()
                } label: {
                    HStack {
                        Text("Capítulos descargados")
                        Spacer()
                        if !downloads.queue.isEmpty {
                            Text("\(downloads.queue.count) en cola")
                                .foregroundStyle(Color.moka)
                        } else {
                            Text(downloads.totalBytes.byteText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker("Páginas simultáneas", selection: $settings.downloadBatch) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Borrar al terminar de leer", isOn: $settings.deleteAfterReading)
                Button {
                    Task {
                        await ImagePipeline.shared.clearCaches()
                        cacheBytes = await ImagePipeline.shared.diskCacheBytes()
                    }
                } label: {
                    HStack {
                        Text("Limpiar caché de imágenes")
                        Spacer()
                        Text(cacheBytes.byteText).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    HStack {
                        Text("Restaurar copia de Mihon")
                        Spacer()
                        if importing { ProgressView() }
                    }
                }
                .disabled(importing)
                Button("Exportar copia (.tachibk)") {
                    do {
                        exportDocument = TachibkDocument(
                            data: try MihonBackupExport.make(library: library, extensions: extensions)
                        )
                    } catch {
                        exportError = error.localizedDescription
                    }
                }
                .disabled(library.entries.isEmpty)
            } header: {
                Text("Datos")
            } footer: {
                Text("La copia usa el formato .tachibk: puedes restaurarla aquí o en Mihon. Lo que ya tienes en MokaReader se conserva y se combina.")
            }

            Section {
                Label("MokaReader es para toda la familia: las extensiones y series para adultos se bloquean siempre.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    clearCookies()
                } label: {
                    HStack {
                        Text("Limpiar cookies de las fuentes")
                        Spacer()
                        if clearingCookies {
                            ProgressView()
                        } else if let cookiesResult {
                            Text(cookiesResult)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(clearingCookies || extensions.installed.isEmpty)
            } header: {
                Text("Avanzado")
            } footer: {
                Text("Borra inicios de sesión y permisos guardados de los sitios. Útil cuando una fuente se queda pegada.")
            }

            Section("Motor de extensiones") {
                HStack {
                    Text("Estado")
                    Spacer()
                    Text(engineText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if !engine.state.isReady {
                    Button("Iniciar motor") {
                        Task { _ = try? await JVMEngine.shared.start() }
                    }
                    .disabled(engine.state == .starting)
                }
            }

            Section("Acerca de") {
                HStack {
                    Text("Versión")
                    Spacer()
                    Text(appVersion).foregroundStyle(.secondary)
                }
                NavigationLink("Licencias y créditos") { LicensesView() }
            }
        }
        .navigationTitle("Ajustes")
        .task { cacheBytes = await ImagePipeline.shared.diskCacheBytes() }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .data,
            defaultFilename: MihonBackupExport.suggestedFileName()
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert(
            "No se pudo exportar",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(exportError ?? "") }
        )
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            restore(from: url)
        }
        .alert(
            importError == nil ? "Copia restaurada" : "No se pudo restaurar",
            isPresented: Binding(
                get: { importSummary != nil || importError != nil },
                set: { if !$0 { importSummary = nil; importError = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(importError ?? importSummary?.text ?? "") }
        )
    }

    private func restore(from url: URL) {
        importing = true
        Task {
            defer { importing = false }
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                // The protobuf decode can chew through megabytes; keep it off the main actor.
                let backup = try await Task.detached(priority: .userInitiated) {
                    try MihonBackup.decode(data)
                }.value
                importSummary = try MihonBackupImporter.restore(
                    backup, into: library, extensions: extensions
                )
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func clearCookies() {
        clearingCookies = true
        cookiesResult = nil
        Task {
            defer { clearingCookies = false }
            var cleared = 0
            for installed in extensions.installed {
                guard let source = installed.sources.first else { continue }
                if (try? await JVMEngine.shared.clearCookies(source: source, installed: installed)) != nil {
                    cleared += 1
                }
            }
            cookiesResult = cleared == 0 ? "Sin cambios" : "Listo (\(cleared))"
        }
    }

    private var engineText: String {
        switch engine.state {
            case .idle: return "Detenido (inicia al usar una fuente)"
            case .starting: return "Iniciando…"
            case .ready(let description): return description
            case .failed(let message): return "Error: \(message)"
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

struct LanguagePicker: View {
    let options: [String]
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section {
                Button(settings.languages.isEmpty ? "Mostrando todos" : "Mostrar todos") {
                    settings.languages = []
                }
            }
            Section {
                ForEach(options, id: \.self) { code in
                    Button {
                        if settings.languages.contains(code) {
                            settings.languages.remove(code)
                        } else {
                            settings.languages.insert(code)
                        }
                    } label: {
                        HStack {
                            Text(Language.displayName(code))
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.languages.contains(code) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Idiomas")
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            Text(Self.text)
                .font(.footnote)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Licencias")
    }

    static let text = """
    MokaReader es software libre (Apache License 2.0).

    MokaReader no aloja, incluye ni recomienda contenido ni repositorios. Las extensiones las \
    agrega el usuario desde repositorios que él mismo elige.

    Componentes de terceros:

    • OpenJDK Mobile — GPL v2 con Classpath Exception. La máquina virtual Java que ejecuta las extensiones.
    • Suwayomi-Server (AndroidCompat) — Mozilla Public License 2.0. La capa de compatibilidad con Android.
    • Host de extensiones y núcleo compartido de TachiyomiAZ — Apache License 2.0, © az4521 y colaboradores.
    • TachiJVMRunner — puente Swift/JNI de TachiyomiAZ iOS (GPL v3; se reemplazará o relicenciará antes de publicar).
    • Formato de extensiones y backups de Mihon / Tachiyomi — Apache License 2.0.

    Gracias a los equipos de Mihon, Tachiyomi, Suwayomi, Aidoku, TachiyomiAZ y OpenJDK.
    """
}

/// The generated backup, handed to the system "save to Files" sheet.
struct TachibkDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
