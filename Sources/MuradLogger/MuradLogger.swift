import Foundation

final public class MuradLogger: Sendable {
    public static let shared = MuradLogger()
    private init() {}

    private let logFileName = "murad_log.txt"
    private let queue = DispatchQueue(label: "com.murad.logger.queue")

    private var logFileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(logFileName)
    }

    public func log(_ message: String,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let fileName = (file as NSString).lastPathComponent
            let logEntry = "[\(timestamp)] [\(fileName):\(line) → \(function)] \(message)\n"

            if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                    handle.seekToEndOfFile()
                    if let data = logEntry.data(using: .utf8) {
                        handle.write(data)
                    }
                    handle.closeFile()
                }
            } else {
                try? logEntry.write(to: self.logFileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    public func uploadLogFile(to urlString: String, completion: @Sendable @escaping (Result<String, Error>) -> Void) {
        queue.async { [ self] in
//            guard let self = self else { return }

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

                // Delete the log file on success
                try? FileManager.default.removeItem(at: self.logFileURL)

                let responseText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Success with no response body"
                DispatchQueue.main.async {
                    completion(.success(responseText))
                }
            }

            task.resume()
        }
    }
}
