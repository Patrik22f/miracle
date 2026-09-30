import Foundation
import Observation

struct InstallableSkill: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
    let repository: URL?

    init(_ skill: AnalyzeResponse.Skill) {
        id = skill.id; name = skill.name; url = skill.url; repository = skill.repositoryUrl
    }
    init(_ skill: SkillLibrary.Entry) {
        id = skill.id; name = skill.name; url = skill.url; repository = nil
    }
    init(id: String, name: String, url: URL, repository: URL? = nil) {
        self.id = id; self.name = name; self.url = url; self.repository = repository
    }
}

actor SkillInstaller {
    private let files = FileManager.default
    private var destinations = Set<String>()
    private let maximumBytes = 20 * 1024 * 1024
    private let fetch: (@Sendable (URL) async throws -> Data)?

    init(fetch: (@Sendable (URL) async throws -> Data)? = nil) { self.fetch = fetch }

    func install(_ skill: InstallableSkill, into root: URL) async throws -> URL {
        guard Self.safeName(skill.name) else { throw failure("This skill has an unsupported name.") }
        let destination = root.appendingPathComponent(skill.name, isDirectory: true)
        guard destinations.insert(destination.path).inserted else { throw failure("Installation is already running.") }
        defer { destinations.remove(destination.path) }
        guard !exists(destination) else { throw failure("A skill with this name is already installed. Existing files were kept.") }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".preflight-install-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        if skill.url.isFileURL {
            try copyPackage(from: skill.url.deletingLastPathComponent(), to: staging)
        } else {
            try await downloadPackage(skill, to: staging)
        }
        let instructions = try String(contentsOf: staging.appendingPathComponent("SKILL.md"), encoding: .utf8)
        guard Self.metadataName(instructions) == skill.name else { throw failure("The downloaded skill does not match this recommendation.") }
        try Task.checkCancellation()
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        guard !exists(destination) else { throw failure("A skill with this name is already installed. Existing files were kept.") }
        // Publish only complete packages. moveItem refuses to overwrite an existing directory.
        try files.moveItem(at: staging, to: destination)
        return destination
    }

    private func exists(_ url: URL) -> Bool { (try? files.attributesOfItem(atPath: url.path)) != nil }

    static func safeName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}$"#, options: .regularExpression) != nil
    }

    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func metadataName(_ content: String) -> String? {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        guard let line = lines[1..<end].first(where: { $0.hasPrefix("name:") }) else { return nil }
        return line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func copyPackage(from source: URL, to staging: URL) throws {
        let sourceValues = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard sourceValues.isDirectory == true, sourceValues.isSymbolicLink != true else { throw failure("The skill folder is unavailable.") }
        let canonicalSource = source.resolvingSymlinksInPath()
        guard let enumerator = files.enumerator(at: canonicalSource, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            throw failure("The skill folder could not be read.")
        }
        var total = 0, count = 0
        while let file = enumerator.nextObject() as? URL {
            if file.lastPathComponent == ".git" { enumerator.skipDescendants(); continue }
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw failure("This skill contains a symbolic link. Install it manually.") }
            guard values.isRegularFile == true else { continue }
            count += 1; total += values.fileSize ?? maximumBytes
            guard count <= 300, total <= maximumBytes else { throw failure("This skill exceeds the installation size limit.") }
            let canonicalFile = file.resolvingSymlinksInPath()
            guard canonicalFile.path.hasPrefix(canonicalSource.path + "/") else { throw failure("This skill contains an invalid file path.") }
            let relative = String(canonicalFile.path.dropFirst(canonicalSource.path.count + 1))
            guard Self.safePath(relative) else { throw failure("This skill contains an invalid file path.") }
            let target = staging.appendingPathComponent(relative)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: file, to: target)
        }
    }

    private struct Tree: Decodable {
        struct Entry: Decodable { let path: String; let mode: String; let type: String; let size: Int? }
        let sha: String
        let truncated: Bool
        let tree: [Entry]
    }

    private func downloadPackage(_ skill: InstallableSkill, to staging: URL) async throws {
        let repository = skill.repository ?? skill.url
        guard repository.scheme == "https", repository.host == "github.com", repository.user == nil, repository.password == nil else {
            throw failure("One-click installation requires a public GitHub source.")
        }
        let parts = repository.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts.prefix(2).allSatisfy(Self.safeName) else { throw failure("The skill repository is invalid.") }
        let repo = parts.prefix(2).joined(separator: "/")
        let treeURL = URL(string: "https://api.github.com/repos/\(repo)/git/trees/HEAD?recursive=1")!
        let tree = try JSONDecoder().decode(Tree.self, from: await download(treeURL, limit: 8_000_000))
        guard !tree.truncated else { throw failure("This repository is too large for one-click installation.") }
        let candidates = tree.tree.filter { $0.type == "blob" && ($0.path == "SKILL.md" || $0.path.hasSuffix("/SKILL.md")) && Self.safePath($0.path) }
        let preferred = candidates.filter {
            let directory = URL(fileURLWithPath: $0.path).deletingLastPathComponent().lastPathComponent
            return directory == skill.name || skill.name.hasSuffix("-" + directory)
        }
        let search = preferred.isEmpty ? candidates : preferred
        guard search.count <= 40 else { throw failure("The skill folder could not be identified. Open its source to install it manually.") }
        var folder: String?
        for candidate in search {
            let data = try await download(rawURL(repo: repo, sha: tree.sha, path: candidate.path), limit: 262_144)
            if let text = String(data: data, encoding: .utf8), Self.metadataName(text) == skill.name {
                guard folder == nil else { throw failure("This repository contains several skills with that name.") }
                folder = String(candidate.path.dropLast("SKILL.md".count))
            }
        }
        guard let folder else { throw failure("The skill was not found in its source repository.") }
        let package = tree.tree.filter { $0.path.hasPrefix(folder) && $0.type != "tree" }
        guard !package.isEmpty, package.count <= 300,
              package.allSatisfy({ $0.type == "blob" && ["100644", "100755"].contains($0.mode) && Self.safePath($0.path) }),
              package.reduce(0, { $0 + ($1.size ?? maximumBytes) }) <= maximumBytes else {
            throw failure("This skill contains unsupported files or exceeds the size limit.")
        }
        var total = 0
        for entry in package {
            let data = try await download(rawURL(repo: repo, sha: tree.sha, path: entry.path), limit: min(4_000_000, maximumBytes - total))
            total += data.count
            let relative = String(entry.path.dropFirst(folder.count))
            guard Self.safePath(relative) else { throw failure("This skill contains an invalid file path.") }
            let target = staging.appendingPathComponent(relative)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            try files.setAttributes([.posixPermissions: entry.mode == "100755" ? 0o755 : 0o644], ofItemAtPath: target.path)
        }
    }

    private func rawURL(repo: String, sha: String, path: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/\(repo)/\(sha)")!.appendingPathComponent(path)
    }

    private func download(_ url: URL, limit: Int) async throws -> Data {
        if let fetch {
            let data = try await fetch(url)
            guard data.count <= limit else { throw failure("A skill file exceeds the size limit.") }
            return data
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Preflight", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", ["api.github.com", "raw.githubusercontent.com"].contains(response.url?.host ?? "") else {
            throw failure("The skill could not be downloaded from GitHub. Try again later.")
        }
        guard response.expectedContentLength <= limit else { throw failure("A skill file exceeds the size limit.") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw failure("A skill file exceeds the size limit.") }
            data.append(byte)
        }
        return data
    }

    private func failure(_ message: String) -> ClientError { .message(message) }
}

@MainActor @Observable
final class SkillInstallModel {
    enum State: Equatable { case installing, installed, failed(String) }
    private(set) var states: [String: State] = [:]
    @ObservationIgnored private let installer = SkillInstaller()
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    func key(_ skill: InstallableSkill, root: URL) -> String { root.path + "/" + skill.name }

    func state(_ skill: InstallableSkill, root: URL) -> State? {
        let key = key(skill, root: root)
        if let state = states[key] { return state }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(skill.name).appendingPathComponent("SKILL.md").path) { return .installed }
        return nil
    }

    func install(_ skill: InstallableSkill, root: URL) {
        let key = key(skill, root: root)
        guard states[key] != .installing else { return }
        states[key] = .installing
        tasks[key] = Task { [weak self, installer] in
            do {
                _ = try await installer.install(skill, into: root)
                self?.states[key] = .installed
            } catch { self?.states[key] = .failed(error.localizedDescription) }
            self?.tasks[key] = nil
        }
    }
}
