// WizardJVMRunner — Apache License 2.0

import CWizardJVMBridge
import Foundation

public enum TachiJVMCompressionError: LocalizedError, Sendable {
    case gzipDecompressionFailed(Int)
    case gzipCompressionFailed(Int)

    public var errorDescription: String? {
        switch self {
            case .gzipDecompressionFailed(let status):
                return "Unable to decompress gzip data (status \(status))."
            case .gzipCompressionFailed(let status):
                return "Unable to compress the backup (status \(status))."
        }
    }
}

/// Gzip for Mihon `.tachibk` backups. The name is kept from the previous
/// bridge so call sites only change their import.
public enum TachiJVMCompression {
    public static func gunzip(_ data: Data) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var outputSize = 0
        let status = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            wjb_gzip_decompress(
                buffer.bindMemory(to: UInt8.self).baseAddress,
                buffer.count,
                &output,
                &outputSize
            )
        }
        guard status == WJBStatusOK, let output else {
            throw TachiJVMCompressionError.gzipDecompressionFailed(
                Int(status.rawValue)
            )
        }
        defer { wjb_buffer_free(output) }
        return Data(bytes: output, count: outputSize)
    }

    public static func gzip(_ data: Data) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var outputSize = 0
        let status = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            wjb_gzip_compress(
                buffer.bindMemory(to: UInt8.self).baseAddress,
                buffer.count,
                &output,
                &outputSize
            )
        }
        guard status == WJBStatusOK, let output else {
            throw TachiJVMCompressionError.gzipCompressionFailed(
                Int(status.rawValue)
            )
        }
        defer { wjb_buffer_free(output) }
        return Data(bytes: output, count: outputSize)
    }
}
