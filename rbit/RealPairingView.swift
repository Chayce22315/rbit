import SwiftUI

struct RealPairingView: View {
    @ObservedObject var store: RbitStore
    @StateObject private var pairing = RbitPairingController.shared
    @StateObject private var vpn = LocalDevVPNMonitor.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingNetworkRequirement = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    statusHeader
                    networkCard
                    instructions
                    mainAction
                }
                .frame(maxWidth: 520)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("pairing")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingNetworkRequirement) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    networkRequirementCard
                        .frame(maxWidth: 520)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("before pairing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("cancel") {
                            showingNetworkRequirement = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo.opacity(0.18), .purple.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)

                Image(systemName: iconName)
                    .font(.system(size: 43, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private var networkCard: some View {
        HStack(spacing: 12) {
            Image(systemName: vpn.connected ? "wifi.router.fill" : "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(vpn.connected ? .green : .orange)
                .frame(width: 38, height: 38)
                .background((vpn.connected ? Color.green : Color.orange).opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(vpn.connected ? "LocalDevVPN is connected" : "LocalDevVPN is not detected")
                    .font(.subheadline.weight(.semibold))
                Text(vpn.connected ? "rbit can continue into the ios 27 pairing handshake." : "connect LocalDevVPN before the actual pairing handshake can finish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("how it works")
                .font(.headline)

            instructionRow("1", "tap start pairing. rbit will explain the local wi-fi permission it needs before ios shows its prompt.")
            instructionRow("2", "open Settings › Privacy & Security › Developer Mode on this iphone.")
            instructionRow("3", "choose rbit when ios shows the pairing request.")
            instructionRow("4", "enter the six-digit pin shown by rbit.")
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.12), in: Circle())

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var networkRequirementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("local network access is required", systemImage: "wifi")
                .font(.headline)

            Text("rbit needs access to your local wi-fi network to pair with and communicate with your iphone. ios will show its permission prompt after you continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("this is only used for the local ios 27 pairing connection. rbit does not need a cloud server for this step.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("continue and request access") {
                showingNetworkRequirement = false
                pairing.start()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
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

                Button("cancel pairing") {
                    pairing.cancel()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)

        case .paired(let name, let model, _):
            VStack(spacing: 10) {
                Label("pairing complete", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
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
            .padding(.vertical, 8)

        case .failed(let message):
            VStack(spacing: 12) {
                Label("pairing failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("try again") {
                    showingNetworkRequirement = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)

        case .requestingNetwork:
            VStack(spacing: 10) {
                ProgressView()
                Text("requesting local wi-fi access…")
                    .font(.subheadline.weight(.medium))
                Text("ios should show its local network permission prompt now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

        case .waitingForDevice:
            VStack(spacing: 10) {
                ProgressView()
                Text("waiting for your iphone…")
                    .font(.subheadline.weight(.medium))
                Text("leave this screen open while completing the developer-mode pairing step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

        case .idle:
            VStack(spacing: 10) {
                Button {
                    showingNetworkRequirement = true
                } label: {
                    Label("start pairing", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if !vpn.connected {
                    Text("LocalDevVPN is still required before the final pairing handshake.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var iconName: String {
        switch pairing.phase {
        case .paired: return "checkmark.shield.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .showPin: return "number.square.fill"
        case .requestingNetwork: return "wifi"
        case .waitingForDevice: return "antenna.radiowaves.left.and.right"
        case .idle: return "iphone.gen3"
        }
    }

    private var title: String {
        switch pairing.phase {
        case .paired: return "iphone paired"
        case .showPin: return "one last step"
        case .failed: return "pairing needs attention"
        case .requestingNetwork: return "requesting local wi-fi access"
        case .waitingForDevice: return "waiting for your iphone"
        case .idle: return "pair with rbit"
        }
    }

    private var subtitle: String {
        switch pairing.phase {
        case .paired: return "the rppairing record is saved on-device."
        case .showPin: return "rbit is waiting for the developer-mode pairing confirmation."
        case .requestingNetwork: return "rbit needs local wi-fi access to discover and communicate with the pairing device."
        case .waitingForDevice: return "rbit is advertising the ios 27 wireless pairing service."
        case .failed: return "the pairing attempt did not complete."
        case .idle: return "rbit uses the ios 27 wireless pairing path."
        }
    }
}
