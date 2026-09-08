import Foundation

struct RbitAppItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let systemImage: String
    let status: String
}

enum RbitPairingState: String {
    case notPaired = "not paired"
    case pairing = "pairing"
    case paired = "paired"
}

@MainActor
final class RbitStore: ObservableObject {
    @Published var pairingState: RbitPairingState = .notPaired
    @Published var localDevVPNEnabled = false
    @Published var appleAccountConnected = false
    @Published var importedApps: [RbitAppItem] = []
    @Published var activity: [String] = ["rbit is ready"]

    func addActivity(_ message: String) {
        activity.insert(message, at: 0)
    }

    func importDemoIPA(name: String) {
        importedApps.insert(
            RbitAppItem(
                name: name,
                subtitle: "imported ipa",
                systemImage: "shippingbox.fill",
                status: "ready"
            ),
            at: 0
        )
        addActivity("imported \(name)")
    }
}
