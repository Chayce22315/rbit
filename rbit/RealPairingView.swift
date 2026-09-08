import SwiftUI

struct RealPairingView: View {
    @ObservedObject var store: RbitStore
    @StateObject private var pairing = RbitPairingController.shared
    @StateObject private var vpn = LocalDevVPNMonitor.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    statusHeader
                    instructions
                    mainAction
                }
                .frame(maxWidth: 520)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("pairing")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("close") { dismiss() }
                }
            }
        }
        .onChange(of: pairing.phase) { _, phase in
            switch phase {
            case .paired:
                store.pairingState = .paired
                store.addActivity("device paired with rbit")
            case .failed(let message):
                store.pairingState = .notPaired
                store.addActivity("pairing failed: \(message)")
            default:
                break
            }
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 58, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            instructionRow("1", "connect LocalDevVPN")
            instructionRow("2", "tap start pairing")
            instructionRow("3", "open Settings › Privacy & Security › Developer Mode")
            instructionRow("4", "choose rbit and enter the six-digit pin")
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.12), in: Circle())
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var mainAction: some View {
        switch pairing.phase {
        case .showPin(let pin):
            VStack(spacing: 14) {
                Text("enter this pin on your iphone")
                    .font(.headline)
                Text(pin)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(7)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                Text("waiting for the pairing handshake to finish…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button("cancel pairing") {
                pairing.cancel()
            }
            .buttonStyle(.bordered)

        case .paired(let name, let model, _):
            VStack(spacing: 10) {
                Label("pairing complete", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Text("\(name) · \(model)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let url = pairing.pairingFileURL {
                    Text(url.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

        case .failed(let message):
            VStack(spacing: 12) {
                Label("pairing failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("try again") { pairing.start() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)

        case .requestingNetwork:
            ProgressView("requesting local network access…")
                .frame(maxWidth: .infinity)

        case .waitingForDevice:
            ProgressView("waiting for your iphone…")
                .frame(maxWidth: .infinity)

        case .idle:
            VStack(spacing: 10) {
                Label(
                    vpn.connected ? "LocalDevVPN connected" : "LocalDevVPN not connected",
                    systemImage: vpn.connected ? "checkmark.circle.fill" : "xmark.circle"
                )
                .font(.headline)
                .foregroundStyle(vpn.connected ? .primary : .secondary)

                Button("start pairing") {
                    pairing.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vpn.connected)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var iconName: String {
        switch pairing.phase {
        case .paired: return "checkmark.shield.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .showPin: return "number.square.fill"
        default: return "iphone.gen3"
        }
    }

    private var title: String {
        switch pairing.phase {
        case .paired: return "iphone paired"
        case .showPin: return "one last step"
        case .failed: return "pairing needs attention"
        default: return "pair with rbit"
        }
    }

    private var subtitle: String {
        switch pairing.phase {
        case .paired: return "the rppairing record is saved on-device."
        case .showPin: return "rbit is now waiting for the developer-mode pairing confirmation."
        default: return "rbit is using the ios 27 wireless pairing path."
        }
    }
}
