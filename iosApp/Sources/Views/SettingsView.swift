import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var extensions: ExtensionManager
    @EnvironmentObject private var engine: EngineStatus

    private let commonLanguages = ["all", "es", "es-419", "en", "pt-BR", "fr", "it", "de", "ja", "ko", "zh"]

    private var languageOptions: [String] {
        var seen = Set<String>()
        let fromSources = extensions.allSources.map(\.lang) + extensions.catalog.flatMap(\.languages)
        return (commonLanguages + fromSources.sorted()).filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section("Lectura") {
                Picker("Modo por defecto", selection: $settings.defaultReadingMode) {
                    ForEach(ReadingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("Manhwa, manhua y webtoons se abren en modo vertical. Puedes cambiar el modo de cada serie desde su ficha o dentro del lector.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Contenido") {
                Toggle("Mostrar contenido +18", isOn: $settings.showNSFW)
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
