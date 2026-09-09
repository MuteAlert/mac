import AppKit
import IOKit.hid
import MuteAlertCore

struct HeadsetObservation {
    let method: String
    let confidence: String
    let muted: Bool?
    let detail: String
}

protocol HeadsetAdapter {
    var name: String { get }
    var implemented: Bool { get }
}

struct VendorAdapter: HeadsetAdapter {
    let name: String
    let implemented: Bool
}

private final class SteelSeriesProvider {
    static let vendorID = 0x1038
    static let productIDs: Set<Int> = [0x12E0, 0x12E5, 0x225D]
    private static let usagePage = 0xFFC0
    private static let reportLength = 64

    var onObservation: ((HeadsetObservation) -> Void)?
    var onDiagnostic: ((String) -> Void)?

    private let condition = NSCondition()
    private let queue = DispatchQueue(label: "com.mutealert.steelseries")
    private var device: IOHIDDevice?
    private var productID = 0
    private var response: [UInt8]?
    private var responseSerial: UInt64 = 0
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var timer: DispatchSourceTimer?
    private var running = false

    func start() {
        condition.lock()
        guard !running else { condition.unlock(); return }
        running = true
        condition.unlock()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(150), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        condition.lock()
        running = false
        let active = device
        let buffer = inputBuffer
        device = nil
        inputBuffer = nil
        condition.broadcast()
        condition.unlock()
        timer?.cancel()
        timer = nil
        queue.sync {}
        if let active, let buffer {
            IOHIDDeviceRegisterInputReportCallback(active, buffer, Self.reportLength, nil, nil)
        }
        buffer?.deallocate()
    }

    func attach(_ candidate: IOHIDDevice) {
        guard property(candidate, kIOHIDVendorIDKey) == Self.vendorID,
              let pid = property(candidate, kIOHIDProductIDKey), Self.productIDs.contains(pid),
              property(candidate, kIOHIDPrimaryUsagePageKey) == Self.usagePage,
              property(candidate, kIOHIDMaxInputReportSizeKey) == Self.reportLength,
              property(candidate, kIOHIDMaxOutputReportSizeKey) == Self.reportLength else { return }
        condition.lock()
        guard running, device == nil else { condition.unlock(); return }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportLength)
        buffer.initialize(repeating: 0, count: Self.reportLength)
        inputBuffer = buffer
        device = candidate
        productID = pid
        condition.unlock()
        IOHIDDeviceRegisterInputReportCallback(candidate, buffer, Self.reportLength, { context, _, _, reportType, reportID, report, reportLength in
            guard let context, reportType == kIOHIDReportTypeInput else { return }
            let provider = Unmanaged<SteelSeriesProvider>.fromOpaque(context).takeUnretainedValue()
            provider.receive(reportID: reportID, bytes: report, count: reportLength)
        }, Unmanaged.passUnretained(self).toOpaque())
        let pidText = String(format: "0x%04X", pid)
        diagnostic("SteelSeries transport attached: VID 0x1038 PID \(pidText)")
    }

    func detach(_ candidate: IOHIDDevice) {
        condition.lock()
        guard let active = device, CFEqual(active, candidate) else { condition.unlock(); return }
        let buffer = inputBuffer
        device = nil
        inputBuffer = nil
        response = nil
        condition.broadcast()
        condition.unlock()
        if let buffer {
            IOHIDDeviceRegisterInputReportCallback(active, buffer, Self.reportLength, nil, nil)
        }
        buffer?.deallocate()
        publish(muted: nil, detail: "SteelSeries receiver disconnected")
        diagnostic("SteelSeries transport detached")
    }

    private func poll() {
        condition.lock()
        guard running, let active = device else { condition.unlock(); return }
        let serial = responseSerial
        condition.unlock()
        var request = [UInt8](repeating: 0, count: Self.reportLength)
        request[0] = 0x06
        request[1] = 0xB0
        let result = request.withUnsafeBytes { raw in
            IOHIDDeviceSetReport(active, kIOHIDReportTypeOutput, CFIndex(0x06),
                                 raw.bindMemory(to: UInt8.self).baseAddress!, Self.reportLength)
        }
        guard result == kIOReturnSuccess else {
            publish(muted: nil, detail: "SteelSeries report request failed (\(result))")
            return
        }
        condition.lock()
        let deadline = Date(timeIntervalSinceNow: 0.25)
        while running && device != nil && responseSerial == serial && condition.wait(until: deadline) {}
        let packet = responseSerial == serial ? nil : response
        condition.unlock()
        guard let packet, let parsed = SteelSeriesState.parse(report: packet) else {
            publish(muted: nil, detail: "SteelSeries receiver did not return a valid state")
            return
        }
        if parsed.online {
            publish(muted: parsed.muted, detail: "Nova Pro Wireless headset is online")
        } else {
            publish(muted: nil, detail: "SteelSeries receiver connected; headset is offline")
        }
    }

    private func receive(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, count: CFIndex) {
        guard count > 0 && count <= 4096 else { return }
        var packet = Array(UnsafeBufferPointer(start: bytes, count: Int(count)))
        if reportID == 0x06, packet.first == 0xB0 { packet.insert(0x06, at: 0) }
        guard packet.count >= 2, packet[0] == 0x06, packet[1] == 0xB0 else { return }
        condition.lock()
        response = packet
        responseSerial &+= 1
        condition.broadcast()
        condition.unlock()
    }

    private func publish(muted: Bool?, detail: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onObservation?(HeadsetObservation(
                method: "SteelSeries device state",
                confidence: muted == nil ? "Unavailable" : "High — validated vendor state",
                muted: muted,
                detail: detail))
        }
    }

    private func diagnostic(_ value: String) {
        DispatchQueue.main.async { [weak self] in self?.onDiagnostic?(value) }
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }
}

final class HeadsetMonitor {
    var onButton: (() -> Void)?
    var onObservation: ((HeadsetObservation) -> Void)?
    private var manager: IOHIDManager?
    private var pressed: Set<String> = []
    private var events: [String] = []
    private let steelSeries = SteelSeriesProvider()
    var status = "Disabled"
    let vendors: [HeadsetAdapter] = [
        VendorAdapter(name: "SteelSeries", implemented: true),
        VendorAdapter(name: "Logitech", implemented: false),
        VendorAdapter(name: "Jabra", implemented: false),
        VendorAdapter(name: "Poly", implemented: false),
        VendorAdapter(name: "Corsair", implemented: false)
    ]

    init() {
        steelSeries.onObservation = { [weak self] observation in
            self?.status = "\(observation.method) · \(observation.confidence)\n\(observation.detail)"
            self?.onObservation?(observation)
        }
        steelSeries.onDiagnostic = { [weak self] in self?.record($0) }
    }

    func start() {
        stop()
        steelSeries.start()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        var matches: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: 0x0B],
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x80]
        ]
        for pid in SteelSeriesProvider.productIDs {
            matches.append([kIOHIDVendorIDKey: SteelSeriesProvider.vendorID,
                            kIOHIDProductIDKey: pid,
                            kIOHIDPrimaryUsagePageKey: 0xFFC0])
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HeadsetMonitor>.fromOpaque(context).takeUnretainedValue().steelSeries.attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HeadsetMonitor>.fromOpaque(context).takeUnretainedValue().steelSeries.detach(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<HeadsetMonitor>.fromOpaque(context).takeUnretainedValue().receive(value)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        status = result == kIOReturnSuccess ?
            "Standard HID enabled; waiting for an observable mute state" :
            "HID access unavailable (\(result)); check Input Monitoring permission"
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            devices.forEach { steelSeries.attach($0) }
        }
    }

    func stop() {
        if let manager {
            IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        steelSeries.stop()
        pressed.removeAll()
        status = "Disabled"
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
            record("Standard HID mute event: usage page \(page), usage \(usage); latched state unknown")
            onButton?()
        } else if !down { pressed.remove(key) }
    }

    private func record(_ event: String) {
        events.append(event)
        if events.count > 128 { events.removeFirst(events.count - 128) }
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
        lines += vendors.map {
            let support = $0.implemented ? "provider enabled" : "unsupported/no observable state"
            return "\($0.name): \(support)"
        }
        lines += events
        return lines.joined(separator: "\n")
    }
}
