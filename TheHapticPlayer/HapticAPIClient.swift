import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case uploadFailed
    case downloadFailed
    case serverUnreachable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .httpError(let code, let message): "Server error (\(code)): \(message)"
        case .uploadFailed: "Failed to upload video"
        case .downloadFailed: "Failed to download haptic file"
        case .serverUnreachable: "Cannot connect to haptic server"
        }
    }
}

actor HapticAPIClient {
    static let shared = HapticAPIClient()

    private let baseURL = URL(string: "http://192.168.1.5:8000/api/v1")!
    private let apiKey: String? = nil
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }

    // MARK: - Health Check

    func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let request = buildRequest(url: url, method: "GET")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            return health.status == "healthy"
        }
        return false
    }

    // MARK: - Analyze Video

    func analyzeVideo(
        fileURL: URL,
        sensitivity: Float = 0.5,
        style: String = "auto",
        bassBoost: Float = 1.0
    ) async throws -> JobCreatedResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("analyze"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sensitivity", value: String(sensitivity)),
            URLQueryItem(name: "style", value: style),
            URLQueryItem(name: "bass_boost", value: String(bassBoost)),
        ]

        let boundary = UUID().uuidString
        let uploadURL = try buildMultipartFile(videoURL: fileURL, boundary: boundary)

        var request = buildRequest(url: components.url!, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, fromFile: uploadURL)

        // Clean up temp multipart file
        try? FileManager.default.removeItem(at: uploadURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 202 {
            return try JSONDecoder().decode(JobCreatedResponse.self, from: data)
        }

        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
    }

    // MARK: - Check Status

    func checkStatus(jobId: String) async throws -> JobStatusResponse {
        let url = baseURL.appendingPathComponent("status/\(jobId)")
        let request = buildRequest(url: url, method: "GET")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(JobStatusResponse.self, from: data)
        }

        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
    }

    // MARK: - Download AHAP

    func downloadAHAP(jobId: String, destinationURL: URL) async throws {
        let url = baseURL.appendingPathComponent("result/\(jobId)")
        let request = buildRequest(url: url, method: "GET")

        let (tempURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            return
        }

        let data = try? Data(contentsOf: tempURL)
        let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
        throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
    }

    // MARK: - Result Info

    func getResultInfo(jobId: String) async throws -> AHAPDownloadInfo {
        let url = baseURL.appendingPathComponent("result/\(jobId)/info")
        let request = buildRequest(url: url, method: "GET")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(AHAPDownloadInfo.self, from: data)
        }

        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
    }

    // MARK: - Helpers

    private func buildRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return request
    }

    private func buildMultipartFile(videoURL: URL, boundary: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload_\(UUID().uuidString).multipart")

        guard let outputStream = OutputStream(url: tempURL, append: false) else {
            throw APIError.uploadFailed
        }
        outputStream.open()
        defer { outputStream.close() }

        let fileName = videoURL.lastPathComponent
        let mimeType = mimeTypeForExtension(videoURL.pathExtension)

        // Write preamble
        let preamble = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n"
        let preambleData = Data(preamble.utf8)
        preambleData.withUnsafeBytes { buffer in
            outputStream.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: preambleData.count)
        }

        // Stream video file in 1MB chunks
        guard let inputStream = InputStream(url: videoURL) else {
            throw APIError.uploadFailed
        }
        inputStream.open()
        defer { inputStream.close() }

        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                outputStream.write(buffer, maxLength: bytesRead)
            } else {
                break
            }
        }

        // Write epilogue
        let epilogue = "\r\n--\(boundary)--\r\n"
        let epilogueData = Data(epilogue.utf8)
        epilogueData.withUnsafeBytes { buffer in
            outputStream.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: epilogueData.count)
        }

        return tempURL
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "mkv": "video/x-matroska"
        case "avi": "video/x-msvideo"
        case "webm": "video/webm"
        default: "video/mp4"
        }
    }
}
