import CryptoKit
import Foundation

/// Downloads Tilawa's model + phoneme corpus on first use and keeps them in Application Support.
///
/// The model and corpus are NPL-1.2 artifacts (free, non-commercial use; see
/// https://github.com/yazinsai/tilawa/blob/main/NOTICE.md), so they're fetched from the upstream
/// release rather than bundled into the app.
nonisolated enum TilawaAssets {
    struct File: Sendable {
        let name: String
        let sha256: String
        let size: Int64
    }

    static let release = "v0.3.0"
    static let baseURL = URL(string: "https://github.com/yazinsai/tilawa/releases/download/v0.3.0/")!

    static let model = File(
        name: "zipformer_interp_gentle_a05.int8.onnx",
        sha256: "eaf099afefbe5cc8c9aee74df864ce7cc69744271e4f3bb46ef6c17612fbe335",
        size: 69_245_985
    )
    static let io = File(
        name: "zipformer_interp_gentle_a05.io.json",
        sha256: "f195c3c33b99d5cb6c8d306f0951d9ad550877c019a79747db3215b804429f9f",
        size: 37_984
    )
    static let corpus = File(
        name: "zipformer_quran.json",
        sha256: "24360c05ec88fcacf3419c1fe6cd81d69e653326a0bf0e4fb507e7b98fc88127",
        size: 5_453_439
    )
    static let all = [model, io, corpus]
    static let totalBytes = all.reduce(Int64(0)) { $0 + $1.size }

    enum AssetError: LocalizedError {
        case badStatus(Int)
        case checksumMismatch(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Download failed (HTTP \(code))."
            case .checksumMismatch: return "The downloaded recognizer was corrupted. Please try again."
            }
        }
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tilawa/\(release)", isDirectory: true)
    }

    static func url(for file: File) -> URL {
        directory.appendingPathComponent(file.name)
    }

    static var isInstalled: Bool {
        all.allSatisfy { file in
            let attrs = try? FileManager.default.attributesOfItem(atPath: url(for: file).path)
            return (attrs?[.size] as? NSNumber)?.int64Value == file.size
        }
    }

    /// Download whatever is missing, verifying each file's SHA-256. `progress` gets 0…1.
    static func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)

        var done: Int64 = 0
        for file in all {
            let destination = url(for: file)
            if let attrs = try? fm.attributesOfItem(atPath: destination.path),
               (attrs[.size] as? NSNumber)?.int64Value == file.size {
                done += file.size
                progress(Double(done) / Double(totalBytes))
                continue
            }
            let base = done
            let reporter = DownloadProgress { written in
                progress(min(1, Double(base + written) / Double(totalBytes)))
            }
            let (temp, response) = try await URLSession.shared.download(
                from: baseURL.appendingPathComponent(file.name),
                delegate: reporter
            )
            defer { try? fm.removeItem(at: temp) }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AssetError.badStatus(http.statusCode)
            }
            guard try sha256(of: temp) == file.sha256 else { throw AssetError.checksumMismatch(file.name) }
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: temp, to: destination)
            done += file.size
            progress(Double(done) / Double(totalBytes))
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let onBytes: @Sendable (Int64) -> Void

        init(onBytes: @escaping @Sendable (Int64) -> Void) {
            self.onBytes = onBytes
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            onBytes(totalBytesWritten)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}
