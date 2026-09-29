import Foundation
import Network

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    var isConnected = true

    private init() {
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                NetworkMonitor.shared.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}
