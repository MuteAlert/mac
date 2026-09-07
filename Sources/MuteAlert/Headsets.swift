import AppKit
import IOKit.hid

struct HeadsetObservation {
    let method: String
    let confidence: String
    let muted: Bool?
}

protocol HeadsetAdapter {
    var name: String { get }
    func observation() -> HeadsetObservation
}

// Protocol slots are explicit about unavailable vendor transport.
struct VendorAdapter: HeadsetAdapter {
    let name: String
    func observation() -> HeadsetObservation {
        HeadsetObservation(method: "Unsupported/no observable state",
                           confidence: "None — \(name) macOS transport not validated", muted: nil)
    }
}

final class HeadsetMonitor {
    var onButton: (() -> Void)?
    private var manager: IOHIDManager?
    private var pressed: Set<String> = []
    private var events: [String] = []
    var status = "Disabled"
    let vendors = ["SteelSeries", "Logitech", "Jabra", "Poly", "Corsair"].map { VendorAdapter(name: $0) }
    func start() {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Only telephony and system-microphone collections. Never open keyboard
        // collections or capture raw reports containing arbitrary user input.
        let matches: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: 0x0B],
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x80]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let monitor = Unmanaged<HeadsetMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.receive(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        status = result == kIOReturnSuccess ? "Standard HID enabled; latched physical state unknown" :
            "HID access unavailable (\(result)); check Input Monitoring permission"
    }
    func stop() {
        if let manager {
            IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil; pressed.removeAll(); status = "Disabled"
    }
    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard (page == 0x0B && (usage == 0x2F || usage == 0xE1)) ||
              (page == 0x01 && usage == 0xA9) else { return }
        let device = IOHIDElementGetDevice(element)
        let key = "\(CFHash(device)):\(IOHIDElementGetCookie(element))"
        let down = IOHIDValueGetIntegerValue(value) != 0
        if down && !pressed.contains(key) {
            pressed.insert(key)
            events.append("Mute button event: usage page \(page), usage \(usage); latched state unknown")
            if events.count > 128 { events.removeFirst(events.count - 128) }
            onButton?()
        } else if !down { pressed.remove(key) }
    }
    func diagnostics() -> String {
        var lines = ["MuteAlert macOS headset diagnostics", status,
                     "No audio, serial numbers, paths, raw reports, or window titles collected."]
        if let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices {
                let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber
                let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber
                lines.append("VID \(vid?.intValue ?? 0) PID \(pid?.intValue ?? 0)")
                if let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] {
                    for element in elements.prefix(256) {
                        lines.append("usagePage=\(IOHIDElementGetUsagePage(element)) usage=\(IOHIDElementGetUsage(element)) reportID=\(IOHIDElementGetReportID(element)) bits=\(IOHIDElementGetReportSize(element))")
                    }
                }
            }
        }
        lines += vendors.map { "\($0.name): \($0.observation().confidence)" }
        lines += events
        return lines.joined(separator: "\n")
    }
}
