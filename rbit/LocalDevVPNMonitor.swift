import Foundation

@MainActor
final class LocalDevVPNMonitor: ObservableObject {
    static let shared = LocalDevVPNMonitor()

    @Published private(set) var connected = false
    @Published private(set) var interfaceName: String?

    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        var address: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&address) == 0 else {
            connected = false
            interfaceName = nil
            return
        }
        defer { freeifaddrs(address) }

        var cursor = address
        while let current = cursor {
            let name = String(cString: current.pointee.ifa_name)
            let flags = current.pointee.ifa_flags
            let family = current.pointee.ifa_addr?.pointee.sa_family
            if name.hasPrefix("utun"), (flags & UInt32(IFF_UP)) != 0, family == UInt8(AF_INET), let sockaddr = current.pointee.ifa_addr {
                let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(INET6_ADDRSTRLEN))
                defer { buffer.deallocate() }
                if getnameinfo(sockaddr, socklen_t(sockaddr.pointee.sa_len), buffer, INET6_ADDRSTRLEN, nil, 0, NI_NUMERICHOST) == 0 {
                    let value = String(cString: buffer)
                    if value.hasPrefix("10.7.0.") {
                        connected = true
                        interfaceName = name
                        return
                    }
                }
            }
            cursor = current.pointee.ifa_next
        }

        connected = false
        interfaceName = nil
    }
}
