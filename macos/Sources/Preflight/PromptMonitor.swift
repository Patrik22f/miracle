import AppKit
import ApplicationServices
import OSLog

struct PromptSnapshot: Equatable, Sendable {
    let text: String
    let appName: String
    let processID: pid_t
    let fieldID: UUID
    let bounds: CGRect?

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

// AX calls can wait on another process. Keep polling off the UI actor, and never overlap reads.
actor PromptReader {
    private var previousElement: AXUIElement?
    private var fieldID = UUID()
    private var failure = "Waiting for a readable prompt field"
    func status() -> String { failure }

    func read(processID: pid_t, appName: String, bundleID: String) -> PromptSnapshot? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let value = attribute(application, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            failure = "Cursor has not exposed a focused field. Use the shortcut or paste."
            return nil
        }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.15)
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXPlaceholderValueAttribute]
            .compactMap { attribute(element, $0) as? String }.joined(separator: " ")
        guard PromptPolicy.accepts(bundleID: bundleID, role: role, subrole: subrole, label: label) else {
            failure = "Waiting for Cursor’s prompt field"
            return nil
        }
        guard let text = attribute(element, kAXValueAttribute) as? String else {
            failure = "This prompt is not readable. Use the shortcut or paste."
            return nil
        }
        if previousElement == nil || !CFEqual(previousElement, element) {
            previousElement = element
            fieldID = UUID()
        }
        var bounds: CGRect?
        if let positionValue = attribute(element, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
           let sizeValue = attribute(element, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            var position = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
               AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size), size.width > 0, size.height > 0 {
                bounds = CGRect(origin: position, size: size)
            }
        }
        return PromptSnapshot(text: text, appName: appName, processID: processID, fieldID: fieldID, bounds: bounds)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

@MainActor
final class PromptMonitor {
    private let reader = PromptReader()
    private var task: Task<Void, Never>?
    var isEnabled: () -> Bool = { false }
    var onSnapshot: (PromptSnapshot?) -> Void = { _ in }
    var onPermission: (Bool) -> Void = { _ in }
    var onStatus: (String) -> Void = { _ in }
    private var lastStatus = ""
    private let logger = Logger(subsystem: "dev.preflight.hackathon", category: "monitor")

    private func report(_ status: String) {
        guard status != lastStatus else { return }
        lastStatus = status
        onStatus(status)
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            logger.notice("\(status, privacy: .public)")
        }
    }

    func start() {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func sample() async {
        let trusted = AXIsProcessTrusted()
        onPermission(trusted)
        guard trusted else { report("Accessibility permission is needed"); return }
        guard isEnabled() else { report("Automatic recommendations paused"); return }
        guard let host = NSWorkspace.shared.frontmostApplication else { onSnapshot(nil); return }
        // Opening our own review UI must keep its recommendations intact.
        guard host.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard let bundleID = host.bundleIdentifier, PromptPolicy.supportedApps.contains(bundleID) else {
            report("Waiting for Cursor")
            onSnapshot(nil)
            return
        }
        let snapshot = await reader.read(processID: host.processIdentifier, appName: host.localizedName ?? "AI app", bundleID: bundleID)
        guard !Task.isCancelled, isEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier else { return }
        if let snapshot {
            report(snapshot.bounds == nil ? "Prompt detected; position unavailable. Open Preflight from the menu bar." : "Following the Cursor prompt")
        } else { report(await reader.status()) }
        onSnapshot(snapshot)
    }
}
