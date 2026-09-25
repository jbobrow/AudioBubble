import Foundation
import Network

/// Reports whether this device is joined to a Wi-Fi network.
///
/// Being joined is what slows a bubble down: the radio has to time-share between the access
/// point's channel and the direct (AWDL) link, or traffic detours through the access point. With
/// Wi-Fi on but no network joined, the direct link gets the radio to itself.
nonisolated final class WiFiMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "audio-bubble.wifi-monitor")

    /// Called on the main queue with the current state, and whenever it changes.
    var onChange: (@MainActor (_ joined: Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Peer-to-peer interfaces (awdl, llw) never count: they're the direct link itself.
            let joined = path.status == .satisfied && path.availableInterfaces.contains {
                $0.type == .wifi && !MeshTransport.isPeerToPeer(interfaceName: $0.name)
            }
            let callback = self?.onChange
            DispatchQueue.main.async { callback?(joined) }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}
