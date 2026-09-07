import Foundation

struct CallConfig: Codable, Identifiable {
    var id: String
    var name: String
    var bundles: String
    var enabled = false
    var warning = true
    var cue = true
    var toggle = true
    var muted = "unmute"
    var unmuted = "mute"
    var marker = "leave|hang up"
    var title = ""
    var threshold = 0.08
    var delay = 0.5
    static let defaults = [
        CallConfig(id: "slack", name: "Slack", bundles: "com.tinyspeck.slackmacgap", marker: "leave"),
        CallConfig(id: "teams", name: "Teams", bundles: "com.microsoft.teams2|com.microsoft.teams"),
        CallConfig(id: "zoom", name: "Zoom", bundles: "us.zoom.xos", marker: "leave|end"),
        CallConfig(id: "meet", name: "Google Meet", bundles: "com.google.Chrome|com.microsoft.edgemac|org.mozilla.firefox|com.brave.Browser|com.apple.Safari", muted: "turn on microphone", unmuted: "turn off microphone", marker: "leave call", title: "meet -|meet –|meet —")
    ]
}

struct Preferences: Codable {
    var step = 2.0
    var sensitivity = 1.5
    var lockVolume = false
    var targetVolume = 1.0
    var showCallIcon = true
    var meterEnabled = false
    var headsetEnabled = false
    var syncInput = false
    var syncCalls = false
    var automaticChecks = false
    var includePrereleases = true
    var calls = CallConfig.defaults
    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: "preferences"),
              let result = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return result
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "preferences")
        }
    }
}
