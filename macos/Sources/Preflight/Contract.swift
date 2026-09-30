import Foundation

// Wire format owned jointly with contracts/*.schema.json. Keep fields additive in v1.
struct AnalyzeRequest: Codable, Sendable {
    let prompt: String
    let app: String?
    var maxSkills = 3
}

struct AnalyzeResponse: Codable, Sendable {
    let schemaVersion: String
    let requestId: String
    let analysis: Analysis
    let effort: Effort
    let model: Model
    let skills: [Skill]
    let meta: Metadata

    struct Analysis: Codable, Sendable {
        let intent: String
        let tags: [String]
        let queries: [String]
    }
    struct Effort: Codable, Sendable { let level: String; let reason: String }
    struct Model: Codable, Sendable { let profile: String; let reason: String }
    struct Metadata: Codable, Sendable {
        let source: String
        let ranking: String
        let durationMs: Int
        let warnings: [String]
        var importedCount: Int? = nil
    }
    struct Skill: Codable, Identifiable, Sendable {
        let id: String
        let name: String
        let source: String
        let description: String
        let url: URL
        let repositoryUrl: URL
        let installs: Int?
        let provenance: String
        let reason: String
        let confidence: Double
        let security: String
        var evaluation: Evaluation? = nil
    }
    struct Evaluation: Codable, Sendable {
        let score: Int
        let threshold: Int
        let criteria: [Criterion]
    }
    struct Criterion: Codable, Identifiable, Sendable {
        let id: String
        let label: String
        let maximum: Int
        let points: Int
    }

    static func demo() throws -> Self {
        // A packaged app stores resources in Contents/Resources; native SwiftPM's
        // generated accessor only searches beside the executable or in its build folder.
        let packaged = Bundle.main.resourceURL?
            .appendingPathComponent("Preflight_Preflight.bundle")
        let resources = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
        guard let url = resources.url(forResource: "demo-response", withExtension: "json") else {
            throw ClientError.message("The demo fixture is missing. Rebuild the app.")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

enum ClientError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

struct APIClient: Sendable {
    var endpoint = URL(string: "http://127.0.0.1:8787/analyze")!

    func library(importSkills: Bool = false) async throws -> SkillLibrary {
        let path = importSkills ? "skills/import" : "skills"
        var request = URLRequest(url: endpoint.deletingLastPathComponent().appendingPathComponent(path))
        request.timeoutInterval = 30
        if importSkills {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ClientError.message("Could not load the skill library. Check that the local backend is running.")
        }
        return try JSONDecoder().decode(SkillLibrary.self, from: data)
    }

    func analyze(prompt: String, app: String?) async throws -> AnalyzeResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(AnalyzeRequest(prompt: prompt, app: app))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClientError.message("The API could not analyze this prompt. Check that the local backend is running.")
        }
        let result = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
        guard result.schemaVersion == "1.0" else {
            throw ClientError.message("The API contract changed. Update the client and backend together.")
        }
        return result
    }
}

struct SkillLibrary: Decodable, Sendable {
    let count: Int
    let installedCount: Int
    let publicCount: Int
    let warnings: [String]
    let skills: [Entry]

    struct Entry: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let description: String
        let source: String
        let provenance: String
        let url: URL
        let scopes: [String]
        let purposes: [String]
    }
}
