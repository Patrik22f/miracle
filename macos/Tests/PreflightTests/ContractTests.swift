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
    #expect(response.meta.source == "catalog")
    #expect(response.skills.first?.installs == nil)
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
