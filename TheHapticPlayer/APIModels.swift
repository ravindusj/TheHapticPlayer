import Foundation

struct JobCreatedResponse: Decodable {
    let jobId: String
    let status: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, message
    }
}

struct JobStatusResponse: Decodable {
    let jobId: String
    let status: String
    let progress: Double
    let createdAt: String?
    let completedAt: String?
    let error: String?
    let fileName: String?
    let durationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, progress, error
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case fileName = "file_name"
        case durationSeconds = "duration_seconds"
    }
}

struct AHAPDownloadInfo: Decodable {
    let jobId: String
    let downloadUrl: String
    let fileSizeBytes: Int
    let durationSeconds: Double
    let totalEvents: Int
    let totalChunks: Int

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case downloadUrl = "download_url"
        case fileSizeBytes = "file_size_bytes"
        case durationSeconds = "duration_seconds"
        case totalEvents = "total_events"
        case totalChunks = "total_chunks"
    }
}

struct HealthResponse: Decodable {
    let status: String
    let service: String
    let version: String
}
