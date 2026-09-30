import Foundation
import Testing
@testable import Preflight

struct SkillInstallationTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preflight-install-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func write(_ value: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("Installing a local skill preserves the entire package and refuses overwrites")
    func localPackage() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source/SKILL.md")
        try write("---\nname: example\ndescription: Example\n---\nInstructions", at: source)
        try write("reference", at: root.appendingPathComponent("source/references/details.md"))
        try write("asset", at: root.appendingPathComponent("source/assets/.config"))
        let skill = InstallableSkill(id: "example", name: "example", url: source)
        let installer = SkillInstaller()
        let destination = try await installer.install(skill, into: root.appendingPathComponent("target"))
        #expect(try String(contentsOf: destination.appendingPathComponent("references/details.md"), encoding: .utf8) == "reference")
        #expect(try String(contentsOf: destination.appendingPathComponent("assets/.config"), encoding: .utf8) == "asset")
        await #expect(throws: (any Error).self) { try await installer.install(skill, into: root.appendingPathComponent("target")) }
        #expect(try String(contentsOf: destination.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("Instructions"))
    }

    @Test("Unsafe names, symlinks, and mismatched packages cannot publish an installation")
    func rejectedPackages() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source/SKILL.md")
        try write("---\nname: example\n---\nInstructions", at: source)
        let installer = SkillInstaller()
        for name in ["../escape", "wrong-name"] {
            await #expect(throws: (any Error).self) {
                try await installer.install(.init(id: name, name: name, url: source), into: root.appendingPathComponent("target"))
            }
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("source/link"), withDestinationURL: source)
        await #expect(throws: (any Error).self) {
            try await installer.install(.init(id: "example", name: "example", url: source), into: root.appendingPathComponent("target"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("target/example").path))
    }

    @Test("Remote installation pins all package files to one revision, including scripts")
    func remotePackage() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = SkillInstaller { url in
            if url.host == "api.github.com" {
                return Data(#"{"sha":"abc123","truncated":false,"tree":[{"path":"skills/example/SKILL.md","mode":"100644","type":"blob","size":50},{"path":"skills/example/scripts/run.sh","mode":"100755","type":"blob","size":15},{"path":"other/private.txt","mode":"100644","type":"blob","size":10}]}"#.utf8)
            }
            #expect(url.path.hasPrefix("/owner/repo/abc123/skills/example/"))
            if url.lastPathComponent == "SKILL.md" { return Data("---\nname: example\n---\nInstructions".utf8) }
            return Data("echo example".utf8)
        }
        let skill = InstallableSkill(id: "example", name: "example", url: URL(string: "https://skills.sh/owner/repo/example")!, repository: URL(string: "https://github.com/owner/repo")!)
        let destination = try await installer.install(skill, into: root)
        #expect(try String(contentsOf: destination.appendingPathComponent("scripts/run.sh"), encoding: .utf8) == "echo example")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("other").path))
    }

    @Test("Network failure leaves no partial installation")
    func networkFailure() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = SkillInstaller { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: (any Error).self) {
            try await installer.install(.init(id: "example", name: "example", url: URL(string: "https://github.com/owner/repo")!), into: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("Paths never escape the package")
    func paths() {
        for path in ["../outside", "/absolute", "a/../outside", "a//b", "a\\b", "a/./b"] { #expect(!SkillInstaller.safePath(path)) }
        #expect(SkillInstaller.safePath("references/readme.md"))
    }

    @Test("Live public installation smoke", .enabled(if: ProcessInfo.processInfo.environment["PREFLIGHT_INSTALL_SMOKE"] == "1"))
    func livePublicPackage() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = InstallableSkill(id: "vercel-labs/agent-skills/vercel-react-best-practices", name: "vercel-react-best-practices", url: URL(string: "https://skills.sh/vercel-labs/agent-skills/vercel-react-best-practices")!, repository: URL(string: "https://github.com/vercel-labs/agent-skills")!)
        let destination = try await SkillInstaller().install(skill, into: root)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("rules").path))
    }
}
