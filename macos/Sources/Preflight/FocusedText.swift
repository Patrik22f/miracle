import AppKit
import ApplicationServices

@MainActor
enum FocusedText {
    struct Capture { let text: String; let appName: String }

    static func requestPermission() {
        // This is the documented AX option key; avoid the legacy mutable C global in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func capture() throws -> Capture {
        guard AXIsProcessTrusted() else {
            throw ClientError.message("Allow Preflight in System Settings → Privacy & Security → Accessibility, then try the shortcut again. You can also paste below.")
        }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw ClientError.message("Focus a prompt field in another app, then press ⌥⌘Return. Or paste your prompt here.")
        }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.4)
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw ClientError.message("This app doesn't expose a focused input. Copy your prompt and paste it below.")
        }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.4)
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        guard subrole != kAXSecureTextFieldSubrole,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            throw ClientError.message("Focus a regular text input, or copy and paste your prompt below.")
        }
        let selected = attribute(element, kAXSelectedTextAttribute) as? String
        let full = attribute(element, kAXValueAttribute) as? String
        let text = (selected?.isEmpty == false ? selected : full)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw ClientError.message("The focused field is empty or unreadable. Paste a prompt below.") }
        guard text.utf16.count <= 12000 else { throw ClientError.message("Select a shorter prompt, up to 12,000 characters.") }
        return Capture(text: text, appName: application.localizedName ?? "Unknown app")
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
}
