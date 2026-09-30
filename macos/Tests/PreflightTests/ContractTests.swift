import Foundation
import Testing
@testable import Preflight

@Test("The shared response decodes in the macOS client")
func decodesSharedContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/analyze-response.json"))
    let response = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
    #expect(response.schemaVersion == "1.0")
    #expect(response.skills.first?.name == "vercel-react-best-practices")
    #expect(response.meta.source == "library")
    #expect(response.skills.first?.installs == nil)
    #expect(response.skills.first?.evaluation?.criteria.count == 12)
    #expect(response.skills.first?.evaluation?.threshold == 70)
    #expect(response.skills.first?.knowledge?.version == "knowledge-v1")
    #expect(response.skills.first?.knowledge?.hash.count == 64)
    #expect(response.skills.first?.knowledge?.evidenceLines.isEmpty == false)
}

@Test("Older responses without evaluation fields remain compatible")
func decodesLegacyContract() throws {
    let response = try AnalyzeResponse.demo()
    var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
    var skills = try #require(payload["skills"] as? [[String: Any]])
    skills[0].removeValue(forKey: "evaluation")
    skills[0].removeValue(forKey: "knowledge")
    payload["skills"] = skills
    let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: JSONSerialization.data(withJSONObject: payload))
    #expect(decoded.skills.first?.evaluation == nil)
    #expect(decoded.skills.first?.knowledge == nil)
}

@MainActor @Test("Copied suggestions preserve original prompt and use local skill paths")
func copiesInstalledSkillPath() throws {
    let model = AppModel()
    model.editPrompt("Fix Swift actor isolation.")
    let response = try AnalyzeResponse.demo()
    var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
    var skills = try #require(payload["skills"] as? [[String: Any]])
    skills[0]["name"] = "swift-concurrency"
    skills[0]["provenance"] = "installed"
    skills[0]["url"] = "file:///example/skills/swift-concurrency/SKILL.md"
    payload["skills"] = skills
    model.result = try JSONDecoder().decode(AnalyzeResponse.self, from: JSONSerialization.data(withJSONObject: payload))
    model.selected = Set(try #require(model.result).skills.map(\.id))
    let copied = model.promptWithSkills(includeSkills: true)
    #expect(copied.hasPrefix("Fix Swift actor isolation."))
    #expect(copied.contains("swift-concurrency: /example/skills/swift-concurrency/SKILL.md"))
    #expect(!copied.contains("file://"))
    #expect(model.promptWithSkills(includeSkills: false) == "Fix Swift actor isolation.")
}

@Test("Optional app is omitted rather than encoded as null")
func requestOmitsApp() throws {
    let request = AnalyzeRequest(prompt: "Say hello", app: nil)
    let data = try JSONEncoder().encode(request)
    let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(payload["prompt"] as? String == "Say hello")
    #expect(payload["app"] == nil)
    #expect(payload["maxSkills"] as? Int == 3)
}

@Test("The bundled demo fixture is available offline")
func bundledDemo() throws {
    let response = try AnalyzeResponse.demo()
    #expect(response.requestId == "demo-response-v1")
    #expect(!response.skills.isEmpty)
}

@MainActor @Test("Editing invalidates old recommendations and selections")
func invalidation() throws {
    let model = AppModel()
    model.result = try .demo()
    model.selected = ["old-selection"]
    model.invalidate()
    #expect(model.result == nil)
    #expect(model.selected.isEmpty)
    #expect(!model.isLoading)
}
