import AppKit
import ApplicationServices

struct PromptSnapshot: Equatable, Sendable {
    let text: String
    let appName: String
    let processID: pid_t
    let fieldID: UUID
    let bounds: CGRect?
    var bundleIdentifier: String? = nil

    func matchesContent(of other: Self) -> Bool {
        text == other.text && processID == other.processID && fieldID == other.fieldID
    }
}

enum PromptPolicy {
    static let supportedApps = ["com.todesktop.230313mzl4w4u92"]

    static func accepts(bundleID: String, role: String, subrole: String, label: String) -> Bool {
        guard supportedApps.contains(bundleID), subrole != kAXSecureTextFieldSubrole,
              [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role) else { return false }
        let label = label.lowercased()
        if ["search", "terminal", "find", "filename", "file name", "editor content", "code editor"].contains(where: label.contains) { return false }
        // IDE code editors expose the same AX role as chat. Require a prompt label there.
        return label.range(of: #"\b(prompt|chat input|message input|ask anything|ask a question|instructions)\b"#, options: .regularExpression) != nil
    }
}
