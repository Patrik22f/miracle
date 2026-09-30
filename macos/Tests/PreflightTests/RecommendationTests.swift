import Foundation
import Testing
@testable import Preflight

struct RecommendationTests {
    @MainActor @Test("Live defaults on and manual editing does not persist a disabled preference", arguments: ["prompt", "context"])
    func liveDefault(field: String) throws {
        let suite = "Preflight.live-default.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "liveCaptureEnabled")
        let model = AppModel(preferences: defaults)
        #expect(model.liveCaptureEnabled)
        if field == "prompt" { model.editPrompt("Manual draft") }
        else { model.editContext("Manual context") }
        #expect(!model.liveCaptureEnabled)
        #expect(AppModel(preferences: defaults).liveCaptureEnabled)
    }

    @MainActor @Test("The captured app determines the target and unsupported apps never inherit it")
    func automaticTarget() async throws {
        let model = AppModel { _, _, _ in try .demo() }
        #expect(model.targetApp == nil)
        let cursor = CapturedPrompt.cursorFixture()
        model.receiveCapture(.captured(cursor))
        await model.task?.value
        #expect(model.targetApp == .cursor)
        let codex = CapturedPrompt(text: cursor.text,
            source: .init(processID: 456, bundleIdentifier: "com.openai.codex", name: "ChatGPT"),
            fieldID: UUID(), supportsAutomaticRecommendations: true)
        model.receiveCapture(.captured(codex))
        #expect(model.targetApp == .codex)
        #expect(model.result == nil)
        await model.task?.value
        #expect(model.result != nil)
        model.receiveCapture(.captured(.init(text: "Unrelated field", source: .fixture)))
        #expect(model.targetApp == nil)
        #expect(model.result == nil)
    }

    @Test("Host detection does not confuse ChatGPT with Codex")
    func hosts() {
        #expect(HostApp.detect(.init(processID: 1, bundleIdentifier: "com.openai.codex", name: "ChatGPT")) == .codex)
        #expect(HostApp.detect(.init(processID: 1, bundleIdentifier: "com.openai.chat", name: "ChatGPT")) == nil)
    }

    @Test("Model profiles use the backend contract and effort is model-specific")
    func recommendations() {
        let models = ModelRecommendation.cursorModels
        #expect(ModelRecommendation.choose(from: models, profile: "fast")?.id == "composer-2.5")
        #expect(ModelRecommendation.choose(from: models, profile: "capable")?.id == "grok-4.7")
        #expect(ModelRecommendation.choose(from: [], profile: "balanced") == nil)
        #expect(ModelRecommendation.effort(for: models[2], requested: "high") == nil)
        #expect(ModelRecommendation.effort(for: models[0], requested: "ultra") == "xhigh")
    }

    @Test("Codex models follow visibility, ordering and exact supported efforts")
    func codex() throws {
        let data = Data(#"{"models":[{"slug":"gpt-6-luna","display_name":"Luna","visibility":"list","priority":3,"supported_reasoning_levels":[{"effort":"low"}]},{"slug":"hidden","display_name":"Hidden","visibility":"hide","priority":1,"supported_reasoning_levels":[]},{"slug":"gpt-6-astra","display_name":"Astra","visibility":"list","priority":2,"supported_reasoning_levels":[{"effort":"medium"},{"effort":"high"}]}]}"#.utf8)
        let models = try ModelRecommendation.decodeCodex(data)
        #expect(models.map(\.id) == ["gpt-6-astra", "gpt-6-luna"])
        #expect(ModelRecommendation.choose(from: models, profile: "fast")?.name == "Luna")
        #expect(ModelRecommendation.effort(for: models[1], requested: "high") == "low")
    }

    @MainActor @Test("Account availability and installation destination persist independently of onboarding")
    func preferences() throws {
        let suite = "Preflight.recommendation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.availableModels(for: .cursor, catalog: ModelCatalog()).map(\.id) == ["grok-4.6"])
        settings.cursorModelIDs = ["composer-2.5"]
        settings.installInProject = true
        #expect(settings.installRoot(for: .cursor) == nil)
        settings.projectPath = "/tmp/example-project"
        let restored = AppSettings(defaults: defaults)
        #expect(!restored.completedOnboarding)
        #expect(restored.availableModels(for: .cursor, catalog: ModelCatalog()).map(\.id) == ["composer-2.5"])
        #expect(restored.installRoot(for: .cursor)?.path == "/tmp/example-project/.cursor/skills")
        #expect(restored.installRoot(for: .codex)?.path == "/tmp/example-project/.codex/skills")
    }
}

struct ModelCatalogRegressionTests {
    @Test("Cursor reads enabled models and declared effort parameters from its own catalog")
    func cursorCatalog() throws {
        let data = Data(#"{"models":[{"name":"grok-4.7","clientDisplayName":"Grok 4.7","supportsAgent":true,"defaultOn":true,"parameterDefinitions":[{"id":"reasoning_effort","parameterType":{"enumParameter":{"values":[{"value":"low"},{"value":"high"},{"value":"xhigh"}]}}}]},{"name":"composer-2.5","supportsAgent":true,"defaultOn":false,"parameterDefinitions":[]},{"name":"hidden","supportsAgent":true,"defaultOn":true,"isHidden":true},{"name":"disabled","supportsAgent":true,"defaultOn":true},{"name":"completion","supportsAgent":false,"defaultOn":true}],"enabled":["composer-2.5"],"disabled":["disabled"]}"#.utf8)
        let models = try ModelRecommendation.decodeCursor(data)
        #expect(models.filter(\.enabled).map(\.id) == ["grok-4.7", "composer-2.5"])
        #expect(models[0].efforts == ["low", "high", "xhigh"])
        #expect(models[1].efforts.isEmpty)
        #expect(models.allSatisfy { $0.host == .cursor })
        #expect(ModelRecommendation.choose(from: models.filter(\.enabled), profile: "fast")?.id == "composer-2.5")
        #expect(ModelRecommendation.choose(from: models.filter(\.enabled), profile: "capable")?.id == "grok-4.7")
    }

    @Test("Missing tiers use the nearest capability, and unsupported efforts never silently drop to medium")
    func fallback() {
        let fast = RecommendedModel(id: "fast", name: "Fast", host: .codex, profile: "fast", efforts: ["low"])
        let balanced = RecommendedModel(id: "balanced", name: "Balanced", host: .codex, profile: "balanced", efforts: ["low", "high"])
        #expect(ModelRecommendation.choose(from: [fast, balanced], profile: "capable") == balanced)
        #expect(ModelRecommendation.effort(supported: ["low", "high"], requested: "medium") == "high")
        #expect(ModelRecommendation.effort(supported: ["low", "extra-high"], requested: "xhigh") == "extra-high")
        #expect(ModelRecommendation.effort(supported: [], requested: "high") == nil)
    }
}

@Test("Read the installed host catalogs", .enabled(if: ProcessInfo.processInfo.environment["PREFLIGHT_VERIFY_LOCAL_MODELS"] == "1"))
func installedHostCatalogs() async throws {
    let codex = try await CodexModelReader().read()
    let cursor = try await CursorModelReader().read()
    #expect(!codex.isEmpty)
    #expect(!cursor.filter(\.enabled).isEmpty)
    #expect(codex.allSatisfy { $0.host == .codex })
    #expect(cursor.allSatisfy { $0.host == .cursor })
    let codexHigh = try #require(ModelRecommendation.choose(from: codex, profile: "capable", requestedEffort: "high"))
    let cursorHigh = try #require(ModelRecommendation.choose(from: cursor.filter(\.enabled), profile: "capable", requestedEffort: "high"))
    #expect(codexHigh.id != cursorHigh.id)
    print("Local catalogs: \(codex.count) Codex models, \(cursor.filter(\.enabled).count) enabled Cursor models. Complex task: \(codexHigh.name) / \(cursorHigh.name).")
}
