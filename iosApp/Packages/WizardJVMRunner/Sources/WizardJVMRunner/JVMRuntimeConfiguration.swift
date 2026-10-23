// WizardJVMRunner — Apache License 2.0

import Foundation

/// Where the bundled JVM lives and what goes on its classpath.
///
/// The resource names (`java_bundle`, `tachiaz-extension-host.jar`,
/// `tachiaz-mobile-shims.jar`, `tachiaz-compat/`) are the layout the CI
/// staging script produces; they are resolved by name from the app bundle.
public struct JVMRuntimeConfiguration: Sendable {
    public let javaHomeURL: URL
    public let frameworksURL: URL
    public let classpathURLs: [URL]
    public let additionalOptions: [String]

    public init(
        javaHomeURL: URL,
        frameworksURL: URL,
        classpathURLs: [URL],
        additionalOptions: [String] = []
    ) {
        self.javaHomeURL = javaHomeURL
        self.frameworksURL = frameworksURL
        self.classpathURLs = classpathURLs
        self.additionalOptions = additionalOptions
    }

    var classpath: String {
        classpathURLs.map(\.path).joined(separator: ":")
    }

    public static func bundled(
        in bundle: Bundle = .main,
        additionalOptions: [String] = []
    ) throws -> JVMRuntimeConfiguration {
        guard let resourcesURL = bundle.resourceURL else {
            throw JVMRuntimeError.invalidConfiguration(
                "Application resource directory is unavailable"
            )
        }
        let fileManager = FileManager.default
        let javaHomeURL = resourcesURL.appendingPathComponent(
            "java_bundle", isDirectory: true
        )
        let hostURL = resourcesURL.appendingPathComponent("tachiaz-extension-host.jar")
        let shimsURL = resourcesURL.appendingPathComponent("tachiaz-mobile-shims.jar")
        let compatURL = resourcesURL.appendingPathComponent(
            "tachiaz-compat", isDirectory: true
        )

        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: javaHomeURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw JVMRuntimeError.invalidConfiguration("Bundled java_bundle is missing")
        }

        // A damaged JDK image can take the whole process down inside
        // JNI_CreateJavaVM. Check the minimal pieces first so a broken
        // bundle fails as a plain Swift error instead.
        let requiredFiles = [
            "lib/modules",
            "conf/net.properties",
            "conf/security/java.security",
            "lib/security/blocked.certs",
            "lib/security/public_suffix_list.dat",
            "lib/tzdb.dat",
            "lib/security/cacerts",
        ]
        for relativePath in requiredFiles {
            let url = javaHomeURL.appendingPathComponent(relativePath)
            var pathIsDirectory: ObjCBool = false
            guard
                fileManager.fileExists(atPath: url.path, isDirectory: &pathIsDirectory),
                !pathIsDirectory.boolValue,
                fileManager.isReadableFile(atPath: url.path)
            else {
                throw JVMRuntimeError.invalidConfiguration(
                    "Bundled JVM runtime file is missing or unreadable: \(relativePath)"
                )
            }
        }
        guard fileManager.fileExists(atPath: hostURL.path) else {
            throw JVMRuntimeError.invalidConfiguration(
                "Bundled extension host JAR is missing"
            )
        }
        guard fileManager.fileExists(atPath: shimsURL.path) else {
            throw JVMRuntimeError.invalidConfiguration(
                "Bundled mobile JVM shims are missing"
            )
        }

        // The VM is statically linked; the Frameworks directory may not
        // physically exist, but java.library.path still wants a value.
        let frameworksURL = bundle.privateFrameworksURL
            ?? bundle.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)

        let compatibilityJars = try fileManager
            .contentsOfDirectory(at: compatURL, includingPropertiesForKeys: nil)
            .filter {
                $0.pathExtension == "jar" && !$0.lastPathComponent.hasPrefix("logback-")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !compatibilityJars.isEmpty else {
            throw JVMRuntimeError.invalidConfiguration(
                "Bundled Suwayomi compatibility JARs are missing"
            )
        }

        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let jvmHome = applicationSupport.appendingPathComponent(
            "JVMHome", isDirectory: true
        )
        try fileManager.createDirectory(at: jvmHome, withIntermediateDirectories: true)

        return JVMRuntimeConfiguration(
            javaHomeURL: javaHomeURL,
            frameworksURL: frameworksURL,
            // The full AndroidCompat surface stays ahead of the host jar;
            // the boot shim is prepended to the boot classpath below.
            classpathURLs: compatibilityJars + [hostURL],
            additionalOptions: [
                "-Xbootclasspath/a:\(shimsURL.path)",
                "-Duser.home=\(jvmHome.path)",
                "-Duser.dir=\(jvmHome.path)",
                "-Djava.io.tmpdir=\(FileManager.default.temporaryDirectory.path)",
                "-XX:ErrorFile=\(jvmHome.appendingPathComponent("hs_err_pid%p.log").path)",
            ] + additionalOptions
        )
    }
}
