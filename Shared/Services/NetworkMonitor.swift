import Foundation
import Network
import Observation

/// Observable wrapper around `NWPathMonitor` so SwiftUI views can react to
/// network reachability without each one spinning up its own monitor.
///
/// The app uses this to surface an "Offline" pill in the ThreadPanel when
/// the active provider is cloud and the network is unreachable, so users
/// understand why their request would fail before tapping "Generate".
///
/// On-device providers (Apple Intelligence, Ollama, LM Studio when local)
/// are unaffected by reachability and should not surface the indicator.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// True when at least one interface (wifi/ethernet/cellular) reports
    /// `.satisfied`. Default to `true` so we don't flash an Offline pill
    /// during the first ~1s before the monitor has reported.
    private(set) var isOnline: Bool = true

    /// Lightweight description for the current path (wifi, cellular, …)
    /// suitable for diagnostics.
    private(set) var interfaceDescription: String = ""

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    private init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.crux.network-monitor", qos: .utility)
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newOnline = path.status == .satisfied
            let newDescription = Self.describe(path)
            Task { @MainActor in
                self.isOnline = newOnline
                self.interfaceDescription = newDescription
            }
        }
        monitor.start(queue: queue)
    }

    nonisolated private static func describe(_ path: NWPath) -> String {
        switch path.status {
        case .satisfied:
            if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
            if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
            if path.usesInterfaceType(.cellular) { return "Cellular" }
            return "Online"
        case .unsatisfied:
            return "Offline"
        case .requiresConnection:
            return "Connecting…"
        @unknown default:
            return ""
        }
    }
}
