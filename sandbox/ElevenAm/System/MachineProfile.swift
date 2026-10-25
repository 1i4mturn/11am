import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit.ps

/// How much 11am asks of this Mac. Chosen from unified memory at launch.
enum MachineTier: String {
    case light, standard, pro, studio

    var title: String {
        switch self {
        case .light: return "Light"
        case .standard: return "Standard"
        case .pro: return "Pro"
        case .studio: return "Studio"
        }
    }

    var guidance: String {
        switch self {
        case .light:
            return "Uses Apple's built-in model for quick work, so nothing extra is loaded into memory. Heavier work waits for the overnight window, or goes to Claude if you add a key."
        case .standard:
            return "Apple's model for quick work, plus room for a small local model (Ollama or LM Studio). Heavy work goes overnight or to Claude."
        case .pro:
            return "Can run a capable local model alongside your apps. Cloud stays optional."
        case .studio:
            return "Can run large local models and act as the home brain for your other devices."
        }
    }
}

enum MemoryPressureLevel: String {
    case normal, warning, critical
}

@MainActor
final class MachineProfile: ObservableObject {
    let chip: String
    let memoryGB: Int
    let tier: MachineTier

    @Published private(set) var onACPower = true
    @Published private(set) var lowPowerMode = false
    @Published private(set) var thermal: ProcessInfo.ThermalState = .nominal
    @Published private(set) var memoryPressure: MemoryPressureLevel = .normal

    private var pressureSource: DispatchSourceMemoryPressure?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        chip = MachineProfile.sysctlString("machdep.cpu.brand_string") ?? "Apple silicon"
        let bytes = ProcessInfo.processInfo.physicalMemory
        memoryGB = Int((Double(bytes) / 1_073_741_824).rounded())
        switch memoryGB {
        case ..<12: tier = .light
        case ..<24: tier = .standard
        case ..<96: tier = .pro
        default: tier = .studio
        }
    }

    func startMonitoring() {
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            let event = source.data
            let level: MemoryPressureLevel = event.contains(.critical) ? .critical : (event.contains(.warning) ? .warning : .normal)
            Task { @MainActor in self?.memoryPressure = level }
        }
        source.resume()
        pressureSource = source
    }

    func refresh() {
        onACPower = MachineProfile.isOnACPower()
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = ProcessInfo.processInfo.thermalState
    }

    /// Seconds since the last keyboard, mouse or trackpad input anywhere on the Mac.
    var secondsIdle: TimeInterval {
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    var isCoolEnough: Bool {
        thermal == .nominal || thermal == .fair
    }

    var thermalTitle: String {
        switch thermal {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        @unknown default: return "Unknown"
        }
    }

    var summary: String {
        "\(chip) · \(memoryGB) GB · \(tier.title)"
    }

    private static func isOnACPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return true }
        guard let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return (type as String) == kIOPSACPowerValue
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map { String(cString: $0) }
        }
    }
}
