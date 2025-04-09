import Foundation



final public class MuradLogger: Sendable {
    public static let shared = MuradLogger()
    private init() {
        
    }

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
            //[\(getDeviceInfo().model)][\(getDeviceInfo().id)]
            let logEntry = "[\(timestamp)][\(appName)][\(appVersion)][\(TimeZone.current.identifier)][\(getDeviceInfo().os)][\(fileName):\(line) → \(function)] \(message)\n"

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
        let id = "SD34E3D32R43TINGF4598"
        let model = "iPhone 6 Plust"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let os = "iOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        return (id, model, os)
     
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


    
    public func clearAllLogs(completion: @Sendable @escaping () -> Void ) {
        queue.async {
            let allLogFiles = (try? FileManager.default.contentsOfDirectory(atPath: self.logsDirectory.path)) ?? []
            let logFiles = allLogFiles.filter { $0.hasPrefix("murad_log") && $0.hasSuffix(".txt") }

            for file in logFiles {
                let fileURL = self.logsDirectory.appendingPathComponent(file)
                try? FileManager.default.removeItem(at: fileURL)
            }

            DispatchQueue.main.async {
                completion()
            }
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
    
    public func exportAllLogsToFile(named filename: String = "murad_full_log.txt", completion: @Sendable @escaping (URL?) -> Void) {
        readAllLogs { logs in
            let fileURL = self.logsDirectory.appendingPathComponent(filename)
            do {
                try logs.write(to: fileURL, atomically: true, encoding: .utf8)
                completion(fileURL)
            } catch {
                print("❌ Failed to write logs to file: \(error)")
                completion(nil)
            }
        }
    }

}
