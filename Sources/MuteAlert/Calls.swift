import AppKit
import ApplicationServices
import MuteAlertCore

struct ActiveCall: Identifiable {
    let id: String
    let name: String
    let pid: pid_t
    let muted: Bool
}

final class CallMonitor {
    private let queue = DispatchQueue(label: "MuteAlert.accessibility", qos: .utility)
    private var busy = false // Accessed only on main thread.
    private var generation = 0
    func invalidate() { generation += 1 }
    static var permitted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    private func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    private func label(_ element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute].compactMap {
            value(element, $0) as? String
        }.joined(separator: " ")
    }
    func poll(configs: [CallConfig], showBadge: Bool, syncCalls: Bool,
              command: (String, Bool?)? = nil, completion: @escaping ([ActiveCall]) -> Void) {
        guard !busy else { return }
        guard Self.permitted else { completion([]); return }
        busy = true
        let currentGeneration = generation
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async { [self] in
            var detected: [ActiveCall] = []
            let deadline = Date().addingTimeInterval(2)
            for config in configs where config.enabled &&
                (showBadge || config.warning || config.toggle || syncCalls) {
                let bundles = Match.tokens(config.bundles)
                for app in apps where bundles.contains((app.bundleIdentifier ?? "").lowercased()) {
                    if Date() >= deadline { break }
                    // Meet is deliberately limited to the foreground browser.
                    // macOS does not offer Windows' capture-session PID gate here.
                    if config.id == "meet" && app.processIdentifier != frontmost { continue }
                    let root = AXUIElementCreateApplication(app.processIdentifier)
                    AXUIElementSetMessagingTimeout(root, 0.1)
                    guard let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] else { continue }
                    for window in windows.prefix(8) {
                        if Date() >= deadline { break }
                        if (value(window, kAXMinimizedAttribute) as? Bool) == true { continue }
                        if config.id == "meet" && !Match.label(label(window), config.title) { continue }
                        var stack = [window]
                        var visited = 0
                        var truncated = false
                        var marker = false
                        var candidates: [(AXUIElement, Bool)] = []
                        while let item = stack.popLast(), visited < 500, Date() < deadline {
                            visited += 1
                            let role = value(item, kAXRoleAttribute) as? String
                            if role == kAXButtonRole {
                                let name = label(item)
                                marker = marker || Match.label(name, config.marker)
                                if Match.label(name, config.muted) { candidates.append((item, true)) }
                                else if Match.label(name, config.unmuted) { candidates.append((item, false)) }
                            }
                            if let children = value(item, kAXChildrenAttribute) as? [AXUIElement] {
                                let remaining = max(0, 500 - visited - stack.count)
                                if children.count > remaining { truncated = true }
                                stack.append(contentsOf: children.prefix(remaining))
                            }
                        }
                        // Ambiguous/partial scans do not authorize a mute action.
                        guard !truncated, stack.isEmpty, visited < 500,
                              marker, candidates.count == 1, Date() < deadline,
                              let candidate = candidates.first else { continue }
                        detected.append(ActiveCall(id: config.id, name: config.name,
                                                   pid: app.processIdentifier, muted: candidate.1))
                        if let command, command.0 == config.id,
                           command.1 == nil || command.1 != candidate.1 {
                            if (value(candidate.0, kAXEnabledAttribute) as? Bool) != false {
                                _ = AXUIElementPerformAction(candidate.0, kAXPressAction as CFString)
                            }
                        }
                        break
                    }
                    if detected.contains(where: { $0.id == config.id }) { break }
                }
            }
            DispatchQueue.main.async { [self] in
                busy = false
                if currentGeneration == generation { completion(detected) }
            }
        }
    }
}
