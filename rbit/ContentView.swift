import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = RbitStore()
    @State private var showingImporter = false
    @State private var showingPairing = false
    @State private var showingSettings = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            home
                .tabItem { Label("home", systemImage: "house.fill") }
                .tag(0)
            library
                .tabItem { Label("apps", systemImage: "square.grid.2x2.fill") }
                .tag(1)
            activity
                .tabItem { Label("activity", systemImage: "clock.arrow.circlepath") }
                .tag(2)
        }
        .sheet(isPresented: $showingPairing) { PairingView(store: store) }
        .sheet(isPresented: $showingSettings) { SettingsView(store: store) }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls { store.importIPA(url: url) }
            case .failure:
                store.addActivity("ipa import cancelled")
            }
        }
    }

    private var home: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    statusCard
                    installCard
                    quickActions
                    recentCard
                }
                .padding()
            }
            .navigationTitle("rbit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 58, height: 58)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 3) {
                Text("rbit").font(.title.bold())
                Text("research • brainstorm • implement • try again")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("device status").font(.headline)
            HStack(spacing: 10) {
                StatusPill(title: "localdevvpn", active: store.localDevVPNEnabled)
                StatusPill(title: "pairing", active: store.pairingState == .paired)
                StatusPill(title: "apple id", active: store.appleAccountConnected)
            }
            Button { showingPairing = true } label: {
                Label(store.pairingState == .paired ? "manage pairing" : "pair this iphone", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var installCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("install an ipa", systemImage: "shippingbox.fill").font(.headline)
            Text("import an ipa and inspect it before sending it through rbit's local pipeline.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { showingImporter = true } label: {
                Label("add ipa", systemImage: "plus")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            QuickAction(title: "pair", icon: "link") { showingPairing = true }
            QuickAction(title: "apps", icon: "square.grid.2x2.fill") { selectedTab = 1 }
            QuickAction(title: "activity", icon: "clock.arrow.circlepath") { selectedTab = 2 }
        }
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("recent").font(.headline)
                Spacer()
                Text("\(store.activity.count)").font(.caption.bold()).foregroundStyle(.secondary)
            }
            ForEach(Array(store.activity.prefix(3).enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var library: some View {
        NavigationStack {
            Group {
                if store.importedApps.isEmpty {
                    ContentUnavailableView("no apps yet", systemImage: "square.grid.2x2",
                                           description: Text("tap + to import your first ipa"))
                } else {
                    List(store.importedApps) { app in
                        HStack(spacing: 14) {
                            Image(systemName: app.systemImage)
                                .font(.title3).frame(width: 42, height: 42)
                                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading) {
                                Text(app.name).font(.headline)
                                Text(app.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(app.status).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("apps")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "plus") }
                }
            }
        }
    }

    private var activity: some View {
        NavigationStack {
            List {
                ForEach(Array(store.activity.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "checkmark.circle")
                }
            }
            .navigationTitle("activity")
        }
    }
}

private struct StatusPill: View {
    let title: String
    let active: Bool
    var body: some View {
        VStack(spacing: 6) {
            Circle().fill(active ? Color.green : Color.secondary.opacity(0.35)).frame(width: 9, height: 9)
            Text(title).font(.caption2).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 9)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct QuickAction: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                Text(title).font(.caption.bold())
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }
}

private struct PairingView: View {
    @ObservedObject var store: RbitStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: store.pairingState == .paired ? "checkmark.shield.fill" : "iphone.gen3")
                    .font(.system(size: 64)).symbolRenderingMode(.hierarchical)
                Text(store.pairingState == .paired ? "iphone paired" : "pair with rbit").font(.title.bold())
                if store.pairingState == .paired {
                    Text("rbit is ready for the local device connection.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. turn on developer mode in settings")
                        Text("2. choose rbit when asked to pair")
                        Text("3. enter the six-digit code shown by rbit")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                Button {
                    store.pairingState = .paired
                    store.addActivity("device paired")
                } label: {
                    Text(store.pairingState == .paired ? "paired" : "start pairing")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(store.pairingState == .paired)
                Spacer()
            }
            .padding().navigationTitle("pairing")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("close") { dismiss() } } }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var store: RbitStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("connection") {
                    Toggle("localdevvpn", isOn: $store.localDevVPNEnabled)
                    LabeledContent("pairing", value: store.pairingState.rawValue)
                }
                Section("apple account") {
                    Toggle("signed-in account", isOn: $store.appleAccountConnected)
                    Text("account credentials will stay on-device when the signing pipeline is connected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("about") {
                    LabeledContent("version", value: "0.1.0")
                    LabeledContent("target", value: "ios 27")
                }
            }
            .navigationTitle("settings")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("done") { dismiss() } } }
        }
    }
}

#Preview { ContentView() }
