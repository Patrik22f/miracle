import AppKit
import ApplicationServices

struct PromptSnapshot: Equatable, Sendable {
    let text: String
    let appName: String
    let processID: pid_t
    let fieldID: UUID
    let bounds: CGRect?
    var bundleIdentifier: String? = nil
    var context: ConversationContext? = nil
    var projectPath: String? = nil

    func matchesContent(of other: Self) -> Bool {
        text == other.text && processID == other.processID && fieldID == other.fieldID && bundleIdentifier == other.bundleIdentifier && context == other.context && projectPath == other.projectPath
    }
}

enum PromptPolicy {
    static let supportedApps = ["com.todesktop.230313mzl4w4u92", "com.openai.codex"]

    static func accepts(bundleID: String, role: String, subrole: String, label: String) -> Bool {
        guard supportedApps.contains(bundleID), subrole != kAXSecureTextFieldSubrole,
              [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role) else { return false }
        let label = label.lowercased()
        if ["search", "terminal", "find", "filename", "file name", "editor content", "code editor"].contains(where: label.contains) { return false }
        // IDE code editors expose the same AX role as chat. Require a prompt label there.
        if label.range(of: #"\b(prompt|chat|message|ask|follow[- ]up|instructions|describe|what (?:would|can)|build anything)\b"#, options: .regularExpression) != nil { return true }
        // Codex's main composer can expose an unlabeled editable text area.
        // Cursor's unlabeled areas may be source editors, so require a label there.
        return bundleID == "com.openai.codex" && role == kAXTextAreaRole && label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
