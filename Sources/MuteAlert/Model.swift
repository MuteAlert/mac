import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import MuteAlertCore

final class Model: ObservableObject {
    @Published var preferences = Preferences.load() { didSet { preferences.save() } }
    @Published var input = InputState()
    @Published var peak = 0.0
    @Published var activeCalls: [ActiveCall] = []
    @Published var message = ""
    @Published var headsetStatus = "Disabled"
    @Published var updateStatus = "Not checked"
    @Published var releaseURL: URL?
    let audio = AudioController()
    let calls = CallMonitor()
    let headsets = HeadsetMonitor()
    private var timer: Timer?
    private var lastPoll = Date.distantPast
    private var lastLock = Date.distantPast
    private var gates: [String: SpeechGate] = [:]
    private var lastHID = Date.distantPast
    private var checking = false
    var onRender: (() -> Void)?
    var chosenCall: ActiveCall? { activeCalls.first(where: { $0.muted }) ?? activeCalls.first }
    init() {
        headsets.onButton = { [weak self] in self?.headsetButton() }
        apply()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
    }
    func apply() {
        calls.invalidate(); activeCalls = []; gates = [:]
        if preferences.meterEnabled { audio.requestAndStart() }
        else { audio.enabled = false; audio.stop() }
        if preferences.headsetEnabled { headsets.start() } else { headsets.stop() }
        headsetStatus = headsets.status
    }
    func stop() { timer?.invalidate(); audio.enabled = false; audio.stop(); headsets.stop() }
    private func tick() {
        input = audio.snapshot()
        peak = min(1, max(0, audio.peak() * preferences.sensitivity))
        if !preferences.meterEnabled { peak = 0 }
        if preferences.lockVolume && input.volumeWritable && Date().timeIntervalSince(lastLock) > 1 {
            lastLock = Date()
            if let current = input.volume, abs(current - preferences.targetVolume) > 0.01 {
                _ = audio.setVolume(preferences.targetVolume)
            }
        }
        if Date().timeIntervalSince(lastPoll) >= 1.5 {
            lastPoll = Date(); pollCalls()
        }
        for call in activeCalls {
            guard let config = preferences.calls.first(where: { $0.id == call.id }), config.warning else { continue }
            var gate = gates[call.id] ?? SpeechGate()
            if gate.update(now: Date.timeIntervalSinceReferenceDate, peak: peak,
                           muted: call.muted, canHear: preferences.meterEnabled && input.muted != true,
                           threshold: config.threshold, delay: config.delay) {
                message = "You're speaking, but \(call.name) is muted."
                if config.cue { NSSound.beep() }
                let content = UNMutableNotificationContent()
                content.title = "MuteAlert"; content.body = message
                UNUserNotificationCenter.current().add(UNNotificationRequest(
                    identifier: "muted-\(call.id)", content: content, trigger: nil))
            }
            gates[call.id] = gate
        }
        if preferences.automaticChecks && !checking {
            let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 86400 { checkUpdates() }
        }
        onRender?()
    }
    func pollCalls(command: (String, Bool?)? = nil) {
        calls.poll(configs: preferences.calls, showBadge: preferences.showCallIcon,
                   syncCalls: preferences.headsetEnabled && preferences.syncCalls,
                   command: command) { [weak self] found in
            guard let self else { return }
            self.activeCalls = found
            self.gates = self.gates.filter { id, _ in found.contains(where: { $0.id == id }) }
        }
    }
    func toggleInput() {
        guard let muted = input.muted, input.muteWritable else {
            message = "This input device does not expose a writable system mute control."; return
        }
        if !audio.setMuted(!muted) { message = "Could not change input mute." }
    }
    func scroll(_ delta: Double) {
        guard let volume = input.volume, input.volumeWritable else {
            message = "This input device does not expose a writable input volume."; return
        }
        let target = min(1, max(0, volume + (delta > 0 ? 1 : -1) * preferences.step / 100))
        if audio.setVolume(target), preferences.lockVolume { preferences.targetVolume = target }
    }
    func toggleCall() {
        guard let call = chosenCall,
              preferences.calls.first(where: { $0.id == call.id })?.toggle == true else { return }
        pollCalls(command: (call.id, nil))
    }
    func focusCall() {
        if let call = chosenCall { NSRunningApplication(processIdentifier: call.pid)?.activate(options: [.activateIgnoringOtherApps]) }
    }
    private func headsetButton() {
        guard preferences.headsetEnabled, Date().timeIntervalSince(lastHID) > 0.4 else { return }
        lastHID = Date()
        let before = input.muted
        let beforeDevice = input.id
        let beforeCall = chosenCall
        // Give native driver/OS handling time to settle to avoid double toggles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.preferences.headsetEnabled else { return }
            let current = self.audio.snapshot()
            if self.preferences.syncInput, let before, current.id == beforeDevice,
               current.muted == before { _ = self.audio.setMuted(!before) }
            if self.preferences.syncCalls, let beforeCall {
                self.pollCalls(command: (beforeCall.id, !beforeCall.muted))
            }
        }
    }
    func notificationsPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func startup(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { message = "Login item: \(error.localizedDescription)" }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MuteAlert-headset-diagnostics.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try headsets.diagnostics().write(to: url, atomically: true, encoding: .utf8) }
            catch { message = error.localizedDescription }
        }
    }
    func checkUpdates() {
        guard !checking else { return }
        checking = true; updateStatus = "Checking…"
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/MuteAlert/mac/releases?per_page=30")!)
        request.timeoutInterval = 15
        request.setValue("MuteAlert-mac", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                      let data, data.count < 2_000_000,
                      let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    self.updateStatus = "Could not check releases. Try again later."; return
                }
                let current = Version(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")!
                let available = releases.filter {
                    ($0["draft"] as? Bool) != true &&
                    (self.preferences.includePrereleases || ($0["prerelease"] as? Bool) != true)
                }.compactMap { item -> (Version, URL)? in
                    guard let tag = item["tag_name"] as? String, let version = Version(tag),
                          let raw = item["html_url"] as? String, let url = URL(string: raw),
                          url.scheme == "https", url.host == "github.com",
                          url.path.hasPrefix("/MuteAlert/mac/releases/") else { return nil }
                    return (version, url)
                }.sorted { $0.0 > $1.0 }.first
                if let available, available.0 > current {
                    self.releaseURL = available.1; self.updateStatus = "A newer release is available."
                } else { self.releaseURL = nil; self.updateStatus = "No newer release found." }
            }
        }.resume()
    }
}
