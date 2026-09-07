import AppKit
import AVFoundation
import CoreAudio

struct InputState {
    var id = AudioDeviceID(0)
    var name = "No input device"
    var volume: Double?
    var muted: Bool?
    var volumeWritable = false
    var muteWritable = false
}

final class AudioController {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var measuredPeak = 0.0
    private var measuredAt = Date.distantPast
    private var observedDevice: AudioDeviceID = 0
    private var notification: NSObjectProtocol?
    var error = "Meter disabled"
    var enabled = false
    init() {
        notification = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
                guard let self, self.enabled, let source = note.object as? AVAudioEngine,
                      source === self.engine else { return }
                self.stop(); self.start()
            }
    }
    deinit {
        if let notification { NotificationCenter.default.removeObserver(notification) }
        stop()
    }
    private func address(_ selector: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeInput,
                         _ element: AudioObjectPropertyElement = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    private func read<T>(_ id: AudioObjectID, _ a: AudioObjectPropertyAddress, into value: inout T) -> Bool {
        var a = a
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr
    }
    private func writable(_ id: AudioObjectID, _ a: AudioObjectPropertyAddress) -> Bool {
        var a = a; var value = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(id, &a, &value) == noErr && value.boolValue
    }
    // Use the master input control only. Never claim a system-wide mute by
    // changing our own audio engine or just one channel of a multi-channel mic.
    func snapshot() -> InputState {
        var result = InputState()
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   address(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal),
                   into: &result.id), result.id != 0 else {
            observedDevice = 0; stop(); return result
        }
        var name: CFString = "Microphone" as CFString
        if read(result.id, address(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal), into: &name) {
            result.name = name as String
        }
        var volume: Float32 = 0
        if read(result.id, address(kAudioDevicePropertyVolumeScalar), into: &volume) {
            result.volume = Double(volume)
            result.volumeWritable = writable(result.id, address(kAudioDevicePropertyVolumeScalar))
        }
        var mute: UInt32 = 0
        if read(result.id, address(kAudioDevicePropertyMute), into: &mute) {
            result.muted = mute != 0
            result.muteWritable = writable(result.id, address(kAudioDevicePropertyMute))
        }
        if observedDevice != result.id {
            observedDevice = result.id
            if enabled { stop(); start() }
        }
        return result
    }
    @discardableResult func setVolume(_ value: Double) -> Bool {
        let state = snapshot()
        guard state.volumeWritable else { return false }
        var v = Float32(min(1, max(0, value)))
        var a = address(kAudioDevicePropertyVolumeScalar)
        return AudioObjectSetPropertyData(state.id, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: v)), &v) == noErr
    }
    @discardableResult func setMuted(_ value: Bool) -> Bool {
        let state = snapshot()
        guard state.muteWritable else { return false }
        var v: UInt32 = value ? 1 : 0
        var a = address(kAudioDevicePropertyMute)
        return AudioObjectSetPropertyData(state.id, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: v)), &v) == noErr
    }
    func peak() -> Double {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(measuredAt) < 0.5 ? measuredPeak : 0
    }
    func requestAndStart() {
        enabled = true
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.enabled else { return }
                if allowed { self.start() } else { self.error = "Microphone permission denied" }
            }
        }
    }
    func start() {
        guard enabled, engine == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            error = "Enable microphone access to display activity"; return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { error = "Input unavailable"; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channels[channel][frame])) }
            }
            self.lock.lock(); self.measuredPeak = Double(peak); self.measuredAt = Date(); self.lock.unlock()
        }
        do { try engine.start(); self.engine = engine; error = "Meter active (audio is never saved)" }
        catch { input.removeTap(onBus: 0); self.error = error.localizedDescription }
    }
    func stop() {
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil
        lock.lock(); measuredPeak = 0; lock.unlock()
    }
}
