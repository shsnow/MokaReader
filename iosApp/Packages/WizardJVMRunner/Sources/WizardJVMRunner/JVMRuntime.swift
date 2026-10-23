// WizardJVMRunner — Apache License 2.0

import CWizardJVMBridge
import Foundation

/// The single in-process Java VM. Creating a second instance in the same
/// process fails: JNI allows one VM per process, forever.
public final class JVMRuntime: @unchecked Sendable {
    private let handle: OpaquePointer

    public init(configuration: JVMRuntimeConfiguration) throws {
        guard configuration.javaHomeURL.isFileURL else {
            throw JVMRuntimeError.invalidConfiguration("JAVA_HOME must be a file URL")
        }
        guard configuration.frameworksURL.isFileURL else {
            throw JVMRuntimeError.invalidConfiguration(
                "Framework directory must be a file URL"
            )
        }
        guard !configuration.classpathURLs.isEmpty else {
            throw JVMRuntimeError.invalidConfiguration("Classpath cannot be empty")
        }

        let optionCopies = configuration.additionalOptions.compactMap { strdup($0) }
        defer { optionCopies.forEach { free($0) } }
        guard optionCopies.count == configuration.additionalOptions.count else {
            throw JVMRuntimeError.startupFailed("Unable to allocate JVM option strings")
        }
        let options: [UnsafePointer<CChar>?] = optionCopies.map { UnsafePointer($0) }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let created = configuration.javaHomeURL.path.withCString { javaHome in
            configuration.frameworksURL.path.withCString { frameworks in
                configuration.classpath.withCString { classpath in
                    options.withUnsafeBufferPointer { buffer in
                        wjb_runtime_create(
                            javaHome,
                            frameworks,
                            classpath,
                            buffer.baseAddress,
                            Int32(buffer.count),
                            &errorPointer
                        )
                    }
                }
            }
        }

        guard let created else {
            throw JVMRuntimeError.startupFailed(
                Self.takeString(errorPointer) ?? "Unknown startup error"
            )
        }
        handle = created
    }

    deinit {
        wjb_runtime_release(handle)
    }

    public func dispatch(_ requestJSON: String) throws -> String {
        var responsePointer: UnsafeMutablePointer<CChar>?
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = requestJSON.withCString { request in
            wjb_runtime_dispatch(handle, request, &responsePointer, &errorPointer)
        }

        let error = Self.takeString(errorPointer)
        guard status == WJBStatusOK else {
            if let responsePointer {
                wjb_string_free(responsePointer)
            }
            throw JVMRuntimeError.dispatchFailed(
                status: Int(status.rawValue),
                message: error ?? "Unknown Java error"
            )
        }
        guard let responsePointer else {
            throw JVMRuntimeError.invalidUTF8Response
        }
        defer { wjb_string_free(responsePointer) }
        guard let response = String(validatingUTF8: responsePointer) else {
            throw JVMRuntimeError.invalidUTF8Response
        }
        return response
    }

    public func dispatch<Request: Encodable, Response: Decodable>(
        _ request: Request,
        as responseType: Response.Type = Response.self,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Response {
        let encoded: Data
        do {
            encoded = try encoder.encode(request)
        } catch {
            throw JVMRuntimeError.encodingFailed
        }
        let responseJSON = try dispatch(String(decoding: encoded, as: UTF8.self))
        do {
            return try decoder.decode(responseType, from: Data(responseJSON.utf8))
        } catch {
            throw JVMRuntimeError.decodingFailed(error.localizedDescription)
        }
    }

    private static func takeString(
        _ pointer: UnsafeMutablePointer<CChar>?
    ) -> String? {
        guard let pointer else { return nil }
        defer { wjb_string_free(pointer) }
        return String(validatingUTF8: pointer)
    }
}
