import AppKit
import SwiftUI
import UserNotifications

final class MeterView: NSView {
    var model: Model!
    var secondary = false
    var menuAction: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        if secondary, let call = model.chosenCall,
           let icon = NSRunningApplication(processIdentifier: call.pid)?.icon {
            icon.draw(in: NSRect(x: 5, y: 3, width: 18, height: 18))
            if call.muted {
                NSColor.systemRed.setStroke()
                let slash = NSBezierPath(); slash.lineWidth = 3
                slash.move(to: NSPoint(x: 5, y: 3)); slash.line(to: NSPoint(x: 23, y: 21)); slash.stroke()
            }
        } else {
            let capsule = NSBezierPath(roundedRect: NSRect(x: 10, y: 8, width: 8, height: 13), xRadius: 4, yRadius: 4)
            NSColor.secondaryLabelColor.setFill(); capsule.fill()
            NSGraphicsContext.saveGraphicsState(); capsule.addClip()
            NSColor.systemGreen.setFill()
            NSRect(x: 10, y: 8, width: 8, height: 13 * model.peak).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.setStroke()
            let stand = NSBezierPath(); stand.lineWidth = 1.5
            stand.move(to: NSPoint(x: 7, y: 13)); stand.line(to: NSPoint(x: 7, y: 10))
            stand.curve(to: NSPoint(x: 21, y: 10), controlPoint1: NSPoint(x: 7, y: 2), controlPoint2: NSPoint(x: 21, y: 2))
            stand.line(to: NSPoint(x: 21, y: 13)); stand.move(to: NSPoint(x: 14, y: 4))
            stand.line(to: NSPoint(x: 14, y: 1)); stand.stroke()
            if model.input.muted == true {
                NSColor.systemRed.setStroke()
                let slash = NSBezierPath(); slash.lineWidth = 2
                slash.move(to: NSPoint(x: 5, y: 2)); slash.line(to: NSPoint(x: 23, y: 22)); slash.stroke()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { menuAction?() }
        else if secondary { model.focusCall() } else { model.toggleInput() }
    }
    override func rightMouseDown(with event: NSEvent) {
        if model.chosenCall != nil { model.toggleCall() } else { menuAction?() }
    }
    override func otherMouseDown(with event: NSEvent) { menuAction?() }
    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaY != 0 { model.scroll(Double(event.scrollingDeltaY)) }
    }
}

struct SettingsView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading) {
            TabView {
                ScrollView {
                    Form {
                        Text(model.input.name).font(.headline)
                        Text("Input volume: " + (model.input.volume.map { "\(Int($0 * 100))%" } ?? "not exposed by device"))
                        Text("System mute: " + (model.input.muted.map { $0 ? "Muted" : "Unmuted" } ?? "not exposed by device"))
                        Toggle("Enable microphone activity meter", isOn: $model.preferences.meterEnabled)
                        Text("Uses microphone permission. Audio is processed locally and never saved. macOS will show its microphone privacy indicator.").font(.caption)
                        Slider(value: $model.preferences.sensitivity, in: 0.25...5) { Text("Meter sensitivity") }
                        Stepper("Volume per scroll step: \(Int(model.preferences.step))%", value: $model.preferences.step, in: 1...20)
                        Toggle("Keep input volume at my chosen level", isOn: $model.preferences.lockVolume)
                        Slider(value: $model.preferences.targetVolume, in: 0...1) { Text("Target: \(Int(model.preferences.targetVolume * 100))%") }
                        Toggle("Show separate active-call icon", isOn: $model.preferences.showCallIcon)
                        HStack {
                            Button("Enable login item") { model.startup(true) }
                            Button("Disable login item") { model.startup(false) }
                        }
                        Text("Microphone: left-click toggles system input mute; scroll changes volume. Call icon: left-click focuses the app. Right-click toggles the detected call. Control-click either icon opens the menu.").font(.caption)
                    }.padding()
                }.tabItem { Text("General") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Experimental: grant Accessibility permission, then enable the integrations you use. Google Meet is detected only in the foreground browser window. Labels must match the app's language.")
                        HStack {
                            Button("Grant Accessibility access") { CallMonitor.requestPermission() }
                            Button("Allow notifications") { model.notificationsPermission() }
                        }
                        ForEach(model.preferences.calls.indices, id: \.self) { index in
                            GroupBox(model.preferences.calls[index].name) {
                                VStack(alignment: .leading) {
                                    Toggle("Enable integration", isOn: $model.preferences.calls[index].enabled)
                                    Toggle("Warn when speaking while muted", isOn: $model.preferences.calls[index].warning)
                                    Toggle("Play audio cue", isOn: $model.preferences.calls[index].cue)
                                    Toggle("Allow call mute controls", isOn: $model.preferences.calls[index].toggle)
                                    TextField("App bundle IDs (| separated)", text: $model.preferences.calls[index].bundles)
                                    TextField("Muted button labels", text: $model.preferences.calls[index].muted)
                                    TextField("Unmuted button labels", text: $model.preferences.calls[index].unmuted)
                                    TextField("In-call button labels", text: $model.preferences.calls[index].marker)
                                    TextField("Window title filter", text: $model.preferences.calls[index].title)
                                    Slider(value: $model.preferences.calls[index].threshold, in: 0.01...0.5) { Text("Speech threshold") }
                                    Slider(value: $model.preferences.calls[index].delay, in: 0.2...3) { Text("Speech delay") }
                                }.padding(5)
                            }
                        }
                    }.padding()
                }.tabItem { Text("Calls") }
                ScrollView {
                    Form {
                        Toggle("Headset mute synchronization", isOn: $model.preferences.headsetEnabled)
                        Toggle("Synchronize system input", isOn: $model.preferences.syncInput)
                        Toggle("Synchronize active call", isOn: $model.preferences.syncCalls)
                        Text(model.headsetStatus)
                        Text("SteelSeries Nova Pro Wireless USB receivers are detected automatically using their vendor mute-state protocol. Standard HID mute buttons remain button events only; Core Audio reports OS mute, not proof of a physical switch. Silence never implies physical mute.")
                        Text("The SteelSeries transport is experimental on macOS. Logitech, Jabra, Poly, Corsair, and other proprietary physical-state protocols remain unsupported.")
                        Text("If needed, grant Input Monitoring permission in System Settings → Privacy & Security, then Apply again.")
                        Button("Export sanitized headset diagnostics…") { model.exportDiagnostics() }
                    }.padding()
                }.tabItem { Text("Headset") }
                Form {
                    Toggle("Check GitHub daily for updates", isOn: $model.preferences.automaticChecks)
                    Toggle("Include prereleases", isOn: $model.preferences.includePrereleases)
                    Text(model.updateStatus)
                    Button("Check now") { model.checkUpdates() }
                    if let url = model.releaseURL { Link("Open release download", destination: url) }
                    Text("Updates are manually installed. Automatic replacement is not enabled in this initial macOS port.").font(.caption)
                }.padding().tabItem { Text("Updates") }
            }
            Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            HStack {
                Text(model.audio.error).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Apply") { model.apply() }.keyboardShortcut(.defaultAction)
            }
        }.padding().frame(minWidth: 620, minHeight: 540)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = Model()
    var primary: NSStatusItem!
    var secondary: NSStatusItem?
    var settingsWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        primary = makeItem(secondary: false)
        model.onRender = { [weak self] in self?.render() }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched"); settings()
        }
    }
    func makeItem(secondary: Bool) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: 28)
        if let button = item.button {
            let view = MeterView(frame: button.bounds)
            view.autoresizingMask = [.width, .height]; view.model = model; view.secondary = secondary
            view.menuAction = { [weak self] in self?.menu() }
            view.setAccessibilityLabel(secondary ? "MuteAlert active call" : "MuteAlert microphone")
            button.addSubview(view)
        }
        return item
    }
    func render() {
        if model.preferences.showCallIcon && model.chosenCall != nil {
            if secondary == nil { secondary = makeItem(secondary: true) }
        } else if let item = secondary { NSStatusBar.system.removeStatusItem(item); secondary = nil }
        let volume = model.input.volume.map { "\(Int($0 * 100))%" } ?? "unavailable"
        let base = "\(model.input.name)\nVolume: \(volume)\nLeft: system input mute | Scroll: volume\nControl-click: Settings menu"
        primary.button?.subviews.first?.toolTip = base + (model.chosenCall != nil ? "\nRight: toggle call mute" : "")
        secondary?.button?.subviews.first?.toolTip = model.chosenCall.map { "\($0.name): \($0.muted ? "Muted" : "Unmuted")\nLeft: focus app | Right: toggle call mute\nControl-click: Settings menu" }
        primary.button?.subviews.first?.needsDisplay = true
        secondary?.button?.subviews.first?.needsDisplay = true
    }
    func menu() {
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ","); settings.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit MuteAlert", action: #selector(quit), keyEquivalent: "q"); quit.target = self
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    @objc func settings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Settings — MuteAlert"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
