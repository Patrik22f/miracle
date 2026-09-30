import Foundation
import Testing
@testable import Preflight

@Suite("Presentation workspace")
struct DemoTests {
    @Test("The two presentation prompts recommend the intended complementary skills")
    func scenarios() {
        #expect(DemoCatalog.analyze(DemoCatalog.scenarios[0].prompt).skills.map(\.name) == ["supabase-postgres-best-practices"])
        #expect(DemoCatalog.analyze(DemoCatalog.scenarios[1].prompt).skills.map(\.name) == ["frontend-design", "copywriting", "swiftui-expert-skill"])
        #expect(DemoCatalog.analyze("Rename the button to Buy now").skills.isEmpty)
        #expect(DemoCatalog.analyze("Add a database for products").skills.map(\.name) == ["supabase-postgres-best-practices"])
        #expect(DemoCatalog.analyze("Prepis marketingove texty a priprav iOS aplikaci").skills.map(\.name) == ["copywriting", "swiftui-expert-skill"])
    }

    @MainActor @Test("Real Cursor prompts drive demo recommendations without contacting the API")
    func typing() async throws {
        let model = AppModel { _, _, _ in
            Issue.record("Demo must not contact the backend")
            throw ClientError.message("Unexpected API call")
        }
        model.loadDemo()
        #expect(model.prompt.isEmpty)
        #expect(model.suggestions.demoMode)
        #expect(model.suggestions.response?.suggestions.map(\.prompt) == DemoCatalog.scenarios.map(\.prompt))
        model.receiveCapture(.captured(.cursorFixture(text: DemoCatalog.scenarios[0].prompt)))
        await model.task?.value
        #expect(model.result?.skills.first?.name == "supabase-postgres-best-practices")
        model.dismissHelpful()
        model.receiveCapture(.captured(.cursorFixture(text: "Find a React performance problem")))
        let obsolete = model.task
        #expect(model.result == nil)
        #expect(!model.helpfulDismissed)
        model.receiveCapture(.captured(.cursorFixture(text: DemoCatalog.scenarios[1].prompt)))
        await obsolete?.value
        await model.task?.value
        #expect(model.result?.skills.count == 3)
        #expect(model.result?.meta.source == "demo")
        #expect(model.selected.count == 3)
        #expect(model.liveCaptureEnabled)
        #expect(model.hasUnreadRecommendation)
        #expect(model.targetApp == .cursor)
        #expect(model.activeSnapshot != nil)
        #expect(model.suggestions.response?.status == "ready")
        #expect(model.suggestions.task == nil)
    }

    @MainActor @Test("Clearing or leaving demo discards pending results and resumes the detected host")
    func exit() async {
        let model = AppModel { _, _, _ in try .demo() }
        model.loadDemo()
        model.receiveCapture(.captured(.cursorFixture(text: DemoCatalog.scenarios[0].prompt)))
        let first = model.task
        model.receiveCapture(.captured(.cursorFixture(text: "")))
        await first?.value
        #expect(model.result == nil)
        #expect(!model.hasError)
        #expect(!model.isLoading)
        model.receiveCapture(.captured(.cursorFixture(text: DemoCatalog.scenarios[1].prompt)))
        let pending = model.task
        model.setDemoMode(false)
        await pending?.value
        #expect(model.result == nil)
        #expect(model.prompt.isEmpty)
        #expect(model.targetApp == nil)
        #expect(!model.suggestions.demoMode)
        #expect(model.suggestions.response == nil)
        model.receiveCapture(.captured(.cursorFixture()))
        #expect(model.targetApp == .cursor)
        await model.task?.value
        #expect(model.result != nil)
    }

    @MainActor @Test("Presentation installations only affect session state and reset on exit")
    func installation() async {
        let model = AppModel()
        let ids = Set(DemoCatalog.skills.prefix(2).map(\.id))
        model.installDemoSkills(ids)
        #expect(model.demoInstalledSkills.isEmpty)
        model.loadDemo()
        model.installDemoSkills(ids.union(["not-in-the-catalog"]))
        #expect(model.demoInstalledSkills == ids)
        model.receiveCapture(.captured(.cursorFixture(text: DemoCatalog.scenarios[1].prompt)))
        #expect(model.demoInstalledSkills == ids)
        model.setDemoMode(false)
        #expect(model.demoInstalledSkills.isEmpty)
        await model.task?.value
    }

    @MainActor @Test("Entering demo rejects an already running backend response")
    func lateBackendResponse() async throws {
        let deferred = DeferredValue<AnalyzeResponse>()
        let model = AppModel { _, _, _ in await deferred.request() }
        model.receiveCapture(.captured(.cursorFixture(text: "Original live request")))
        let pending = model.task
        await deferred.waitUntilRequested()
        model.loadDemo()
        await deferred.resolve(try .demo())
        await pending?.value
        #expect(model.result == nil)
        #expect(model.prompt.isEmpty)
        #expect(!model.isLoading)
        model.receiveCapture(.captured(.cursorFixture(text: DemoCatalog.scenarios[0].prompt)))
        await model.task?.value
        #expect(model.result?.skills.map(\.name) == ["supabase-postgres-best-practices"])
    }

    @Test("The offline web workspace ships with all its local resources")
    func resources() throws {
        for (name, ext) in [("index", "html"), ("style", "css"), ("demo", "js")] {
            let url = try #require(AnalyzeResponse.resources.url(forResource: name, withExtension: ext, subdirectory: "Demo"))
            #expect(!(try Data(contentsOf: url)).isEmpty)
        }
    }
}
