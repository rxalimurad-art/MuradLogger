import Foundation
#if canImport(UIKit)
import UIKit
#endif


final public class MuradLogger: Sendable {
    public static let shared = MuradLogger()
    private init() {}

    private let logFileName = "murad_log.txt"
    private let maxLogFileSize: UInt64 = 100 * 1024 // 100 KB
    private let queue = DispatchQueue(label: "com.murad.logger.queue")

    private var logsDirectory: URL {
        FileManager.default.temporaryDirectory
    }

    private var logFileURL: URL {
        logsDirectory.appendingPathComponent(logFileName)
    }

    // MARK: - Logging with rotation

    public func log(_ message: String,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.rotateLogFileIfNeeded()

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let fileName = (file as NSString).lastPathComponent

            // 📦 App Info
            let bundle = Bundle.main
            let appName = bundle.infoDictionary?["CFBundleName"] as? String ?? "UnknownApp"
            let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
            let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"

           

            // 📝 Compose log entry
            let logEntry =
            """
            [\(timestamp)]
            App: \(appName) v\(appVersion) (\(buildNumber))
            Device: \(getDeviceInfo().model) [\(getDeviceInfo().id)]
            OS: \(getDeviceInfo().os)
            [\(fileName):\(line) → \(function)]
            \(message)

            """

            if FileManager.default.fileExists(atPath: self.logFileURL.path),
               let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                handle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try? logEntry.write(to: self.logFileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private func getDeviceInfo() -> (id: String, model: String, os: String) {
        #if canImport(UIKit)
        let id = UIDevice.current.identifierForVendor?.uuidString ?? "UnknownDevice"
        let model = UIDevice.current.model
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let os = "iOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        return (id, model, os)
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let os = "Unknown OS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        return ("UnknownDevice", "UnknownModel", os)
        #endif
    }


    private func rotateLogFileIfNeeded() {
        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? UInt64,
              fileSize >= maxLogFileSize else {
            return
        }

        // Find next available log number
        var index = 1
        var rotatedURL: URL
        repeat {
            rotatedURL = logsDirectory.appendingPathComponent("murad_log_\(index).txt")
            index += 1
        } while FileManager.default.fileExists(atPath: rotatedURL.path)

        try? FileManager.default.moveItem(at: logFileURL, to: rotatedURL)
    }

    // MARK: - Upload current log file only (same as before)

    public func uploadLogFile(to urlString: String, completion: @Sendable @escaping (Result<String, Error>) -> Void) {
        queue.async { [self] in
            guard let fileData = try? Data(contentsOf: self.logFileURL),
                  FileManager.default.fileExists(atPath: self.logFileURL.path),
                  let url = URL(string: urlString) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MuradLogger", code: 400, userInfo: [
                        NSLocalizedDescriptionKey: "Log file not found or URL is invalid."
                    ])))
                }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.httpBody = fileData

            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }

                try? FileManager.default.removeItem(at: self.logFileURL)

                let responseText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Success with no response body"
                DispatchQueue.main.async {
                    completion(.success(responseText))
                }
            }

            task.resume()
        }
    }

    // MARK: - Return contents of all log files

    public func readAllLogs(completion: @Sendable @escaping (String) -> Void) {
        queue.async {
            let allLogFiles = (try? FileManager.default.contentsOfDirectory(atPath: self.logsDirectory.path)) ?? []
            let logFiles = allLogFiles
                .filter { $0.hasPrefix("murad_log") && $0.hasSuffix(".txt") }
                .sorted()

            var combined = ""
            for file in logFiles {
                let fileURL = self.logsDirectory.appendingPathComponent(file)
                if let content = try? String(contentsOf: fileURL) {
                    combined += content
                }
            }

            DispatchQueue.main.async {
                completion(combined)
            }
        }
    }
}
