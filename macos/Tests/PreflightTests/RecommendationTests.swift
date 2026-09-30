import Foundation
import Testing
@testable import Preflight

struct RecommendationTests {
    @MainActor @Test("Live defaults on and manual editing does not persist a disabled preference")
    func liveDefault() throws {
        let suite = "Preflight.live-default.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(preferences: defaults)
        #expect(model.liveCaptureEnabled)
        model.editPrompt("Manual draft")
        #expect(!model.liveCaptureEnabled)
        #expect(AppModel(preferences: defaults).liveCaptureEnabled)
        model.setLiveCaptureEnabled(false)
        #expect(!AppModel(preferences: defaults).liveCaptureEnabled)
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
        #expect(ModelRecommendation.effort(for: models[0], requested: "ultra") == "medium")
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
