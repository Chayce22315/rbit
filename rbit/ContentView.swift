import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = RbitStore()
    @State private var showingImporter = false
    @State private var showingPairing = false
    @State private var showingSettings = false
    @State private var selectedTab = 0

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(height: proxy.size.height)
            TabView(selection: $selectedTab) {
                home(metrics: metrics)
                    .tabItem { Label("home", systemImage: "house.fill") }
                    .tag(0)
                library(metrics)
                    .tabItem { Label("apps", systemImage: "square.grid.2x2.fill") }
                    .tag(1)
                activity(metrics)
                    .tabItem { Label("activity", systemImage: "clock.arrow.circlepath") }
                    .tag(2)
            }
        }
        .sheet(isPresented: $showingPairing) { RealPairingView(store: store) }
        .sheet(isPresented: $showingSettings) { SettingsView(store: store) }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls { store.importIPA(url: url) }
            case .failure(let error):
                store.addActivity("ipa import failed: \(error.localizedDescription)")
            }
        }
    }

    private func home(metrics: LayoutMetrics) -> some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: metrics.sectionSpacing) {
                    header(metrics)
                    statusCard(metrics)
                    installCard(metrics)
                    quickActions(metrics)
                    recentCard(metrics)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("rbit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("settings")
                }
            }
        }
    }

    private func header(_ metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.cardSpacing) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: metrics.iconSize, weight: .semibold))
                .frame(width: metrics.iconBox, height: metrics.iconBox)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: metrics.cornerRadius - 3))

            VStack(alignment: .leading, spacing: 4) {
                Text("rbit")
                    .font(metrics.titleFont.bold())
                Text("research • brainstorm • implement • try again")
                    .font(metrics.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("device status")
                .font(metrics.headingFont)

            HStack(spacing: metrics.cardSpacing) {
                StatusPill(title: "localdevvpn", active: store.localDevVPNEnabled, metrics: metrics)
                StatusPill(title: "pairing", active: store.pairingState == .paired, metrics: metrics)
                StatusPill(title: "apple id", active: store.appleAccountConnected, metrics: metrics)
            }

            Button { showingPairing = true } label: {
                Label(
                    store.pairingState == .paired ? "manage pairing" : "pair this iphone",
                    systemImage: "link"
                )
                .font(metrics.buttonFont)
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.buttonVerticalPadding)
            }
            .buttonStyle(.bordered)
        }
        .cardStyle(metrics)
    }

    private func installCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Label("install an ipa", systemImage: "shippingbox.fill")
                .font(metrics.headingFont)

            Text("import an ipa and keep it on-device for the local rbit pipeline.")
                .font(metrics.bodyFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button { showingImporter = true } label: {
                Label("add ipa", systemImage: "plus")
                    .font(metrics.buttonFont.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.buttonVerticalPadding)
            }
            .buttonStyle(.borderedProminent)
        }
        .cardStyle(metrics, material: false)
    }

    private func quickActions(_ metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.cardSpacing) {
            QuickAction(title: "pair", icon: "link", metrics: metrics) { showingPairing = true }
            QuickAction(title: "apps", icon: "square.grid.2x2.fill", metrics: metrics) { selectedTab = 1 }
            QuickAction(title: "activity", icon: "clock.arrow.circlepath", metrics: metrics) { selectedTab = 2 }
        }
    }

    private func recentCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack {
                Text("recent")
                    .font(metrics.headingFont)
                Spacer()
                Text("\(store.activity.count)")
                    .font(metrics.captionFont.bold())
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(store.activity.prefix(metrics.recentRows).enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(metrics.bodyFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(metrics)
    }

    private func library(_ metrics: LayoutMetrics) -> some View {
        NavigationStack {
            Group {
                if store.importedApps.isEmpty {
                    ContentUnavailableView(
                        "no apps yet",
                        systemImage: "square.grid.2x2",
                        description: Text("tap + to import your first ipa")
                    )
                } else {
                    List {
                        ForEach(store.importedApps) { app in
                            HStack(spacing: metrics.cardSpacing) {
                                Image(systemName: app.systemImage)
                                    .font(metrics.rowIconFont)
                                    .frame(width: metrics.rowIconBox, height: metrics.rowIconBox)
                                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name)
                                        .font(metrics.rowTitleFont)
                                        .lineLimit(1)
                                    Text(app.subtitle)
                                        .font(metrics.captionFont)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 8)

                                Text(app.status)
                                    .font(metrics.captionFont)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, metrics.rowVerticalPadding)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.removeApp(app)
                                } label: {
                                    Label("delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("apps")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("add ipa")
                }
            }
        }
    }

    private func activity(_ metrics: LayoutMetrics) -> some View {
        NavigationStack {
            List {
                ForEach(Array(store.activity.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "checkmark.circle")
                        .font(metrics.bodyFont)
                }
            }
            .navigationTitle("activity")
        }
    }
}

private struct LayoutMetrics {
    let isTall: Bool

    init(height: CGFloat) {
        isTall = height >= 760
    }

    var horizontalPadding: CGFloat { isTall ? 20 : 16 }
    var verticalPadding: CGFloat { isTall ? 24 : 16 }
    var sectionSpacing: CGFloat { isTall ? 22 : 16 }
    var cardSpacing: CGFloat { isTall ? 14 : 11 }
    var cornerRadius: CGFloat { isTall ? 24 : 20 }
    var iconSize: CGFloat { isTall ? 36 : 32 }
    var iconBox: CGFloat { isTall ? 64 : 56 }
    var titleFont: Font { isTall ? .title : .title3 }
    var headingFont: Font { isTall ? .headline : .subheadline.weight(.semibold) }
    var bodyFont: Font { isTall ? .subheadline : .footnote }
    var captionFont: Font { isTall ? .caption : .caption2 }
    var buttonFont: Font { isTall ? .body : .subheadline }
    var buttonVerticalPadding: CGFloat { isTall ? 7 : 5 }
    var rowIconFont: Font { isTall ? .title3 : .body }
    var rowTitleFont: Font { isTall ? .headline : .subheadline.weight(.semibold) }
    var rowIconBox: CGFloat { isTall ? 46 : 40 }
    var rowVerticalPadding: CGFloat { isTall ? 6 : 4 }
    var recentRows: Int { isTall ? 4 : 3 }
}

private extension View {
    func cardStyle(_ metrics: LayoutMetrics, material: Bool = true) -> some View {
        padding(metrics.isTall ? 18 : 14)
            .background(
                material
                    ? AnyShapeStyle(.thinMaterial)
                    : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                in: RoundedRectangle(cornerRadius: metrics.cornerRadius)
            )
    }
}

private struct StatusPill: View {
    let title: String
    let active: Bool
    let metrics: LayoutMetrics

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)
            Text(title)
                .font(metrics.captionFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.isTall ? 11 : 9)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct QuickAction: View {
    let title: String
    let icon: String
    let metrics: LayoutMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
                    .font(metrics.captionFont.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.isTall ? 15 : 11)
        }
        .buttonStyle(.bordered)
    }
}

private struct PairingView: View {
    @ObservedObject var store: RbitStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Image(systemName: store.pairingState == .paired ? "checkmark.shield.fill" : "iphone.gen3")
                        .font(.system(size: 64))
                        .symbolRenderingMode(.hierarchical)
                        .padding(.top, 12)

                    Text(store.pairingState == .paired ? "iphone paired" : "pair with rbit")
                        .font(.title.bold())

                    if store.pairingState == .paired {
                        Text("rbit is ready for the local device connection.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("1. turn on developer mode in settings")
                            Text("2. choose rbit when asked to pair")
                            Text("3. enter the six-digit code shown by rbit")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }

                    Button {
                        store.pairingState = .paired
                        store.addActivity("device paired")
                    } label: {
                        Text(store.pairingState == .paired ? "paired" : "start pairing")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.pairingState == .paired)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("storage") {
                    LabeledContent("imported ipas", value: "\(store.importedApps.count)")
                    Text("imported files are kept in rbit's private application support storage, not in the shared Files folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("about") {
                    LabeledContent("version", value: "0.2.0")
                    LabeledContent("target", value: "ios 27")
                }
            }
            .navigationTitle("settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("done") { dismiss() }
                }
            }
        }
    }
}

#Preview { ContentView() }
