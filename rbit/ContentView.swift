import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = RbitStore()
    @StateObject private var vpn = LocalDevVPNMonitor.shared
    @StateObject private var pairing = RbitPairingController.shared
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
            .tint(.indigo)
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
        .onChange(of: pairing.phase) { _, phase in
            if case .paired = phase {
                store.pairingState = .paired
            }
        }
    }

    private func home(metrics: LayoutMetrics) -> some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: metrics.sectionSpacing) {
                    hero(metrics)
                    statusCard(metrics)
                    installCard(metrics)
                    overviewCard(metrics)
                    quickActions(metrics)
                    recentCard(metrics)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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

    private func hero(_ metrics: LayoutMetrics) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [.indigo, .purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.13))
                .frame(width: 150, height: 150)
                .offset(x: 205, y: -50)

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 110, height: 110)
                .offset(x: 260, y: 55)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.title2.bold())
                    Text("rbit")
                        .font(metrics.titleFont.bold())
                }

                Text("research • brainstorm • implement • try again")
                    .font(metrics.captionFont.weight(.medium))
                    .opacity(0.9)

                HStack(spacing: 8) {
                    HeroBadge(title: vpn.connected ? "vpn ready" : "vpn offline", icon: vpn.connected ? "checkmark" : "xmark")
                    HeroBadge(title: pairing.isRunning ? "pairing" : (store.pairingState == .paired ? "paired" : "ready"), icon: pairing.isRunning ? "antenna.radiowaves.left.and.right" : "iphone.gen3")
                }
            }
            .foregroundStyle(.white)
            .padding(metrics.isTall ? 22 : 18)
        }
        .frame(height: metrics.isTall ? 190 : 168)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private func statusCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack {
                Label("device status", systemImage: "iphone.gen3")
                    .font(metrics.headingFont)
                Spacer()
                Circle()
                    .fill(vpn.connected ? .green : .orange)
                    .frame(width: 9, height: 9)
            }

            HStack(spacing: 9) {
                StatusPill(title: "localdevvpn", active: vpn.connected, detail: vpn.interfaceName ?? "not detected", metrics: metrics)
                StatusPill(title: "pairing", active: store.pairingState == .paired, detail: store.pairingState.rawValue, metrics: metrics)
                StatusPill(title: "apple id", active: store.appleAccountConnected, detail: store.appleAccountConnected ? "connected" : "not connected", metrics: metrics)
            }

            Button { showingPairing = true } label: {
                Label(
                    store.pairingState == .paired ? "manage pairing" : "pair this iphone",
                    systemImage: store.pairingState == .paired ? "checkmark.circle.fill" : "link"
                )
                .font(metrics.buttonFont.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.buttonVerticalPadding)
            }
            .buttonStyle(.borderedProminent)
        }
        .cardStyle(metrics)
    }

    private func installCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("install an ipa", systemImage: "shippingbox.fill")
                        .font(metrics.headingFont)
                    Text("keep imported apps on-device and ready for the signing pipeline.")
                        .font(metrics.bodyFont)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.importedApps.count)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.tint)
            }

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

    private func overviewCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("pipeline")
                .font(metrics.headingFont)

            HStack(spacing: 0) {
                PipelineStep(icon: "doc.badge.plus", title: "import", active: !store.importedApps.isEmpty)
                PipelineConnector(active: !store.importedApps.isEmpty)
                PipelineStep(icon: "signature", title: "sign", active: false)
                PipelineConnector(active: false)
                PipelineStep(icon: "iphone.gen3", title: "install", active: false)
            }

            Text("import is ready. signing and device installation are the next pipeline stages.")
                .font(metrics.captionFont)
                .foregroundStyle(.secondary)
        }
        .cardStyle(metrics)
    }

    private func quickActions(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("quick actions")
                .font(metrics.headingFont)

            HStack(spacing: metrics.cardSpacing) {
                QuickAction(title: "pair", icon: "link", tint: .indigo, metrics: metrics) { showingPairing = true }
                QuickAction(title: "apps", icon: "square.grid.2x2.fill", tint: .purple, metrics: metrics) { selectedTab = 1 }
                QuickAction(title: "activity", icon: "clock.arrow.circlepath", tint: .blue, metrics: metrics) { selectedTab = 2 }
            }
        }
    }

    private func recentCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack {
                Label("recent", systemImage: "sparkles")
                    .font(metrics.headingFont)
                Spacer()
                Text("\(store.activity.count)")
                    .font(metrics.captionFont.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if store.activity.isEmpty {
                Text("nothing has happened yet")
                    .font(metrics.bodyFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.activity.prefix(metrics.recentRows).enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: index == 0 ? "bolt.fill" : "checkmark.circle.fill")
                            .foregroundStyle(index == 0 ? Color.indigo : Color.secondary)
                        Text(item)
                            .font(metrics.bodyFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(metrics)
    }

    private func library(_ metrics: LayoutMetrics) -> some View {
        NavigationStack {
            Group {
                if store.importedApps.isEmpty {
                    ContentUnavailableView {
                        Label("no apps yet", systemImage: "square.grid.2x2")
                    } description: {
                        Text("import an ipa and it will appear here with its local status.")
                    } actions: {
                        Button("import ipa") { showingImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(store.importedApps) { app in
                                AppRow(app: app, metrics: metrics)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            store.removeApp(app)
                                        } label: {
                                            Label("delete", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            Text("\(store.importedApps.count) imported")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemGroupedBackground))
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
            Group {
                if store.activity.isEmpty {
                    ContentUnavailableView("no activity", systemImage: "clock.arrow.circlepath")
                } else {
                    List {
                        ForEach(Array(store.activity.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(index == 0 ? Color.indigo.opacity(0.14) : Color.secondary.opacity(0.10))
                                    Image(systemName: index == 0 ? "bolt.fill" : "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(index == 0 ? .indigo : .secondary)
                                }
                                .frame(width: 34, height: 34)

                                Text(item)
                                    .font(metrics.bodyFont)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 7)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemGroupedBackground))
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
    var sectionSpacing: CGFloat { isTall ? 18 : 14 }
    var cardSpacing: CGFloat { isTall ? 13 : 10 }
    var cornerRadius: CGFloat { isTall ? 24 : 20 }
    var titleFont: Font { isTall ? .title : .title2 }
    var headingFont: Font { isTall ? .headline : .subheadline.weight(.semibold) }
    var bodyFont: Font { isTall ? .subheadline : .footnote }
    var captionFont: Font { isTall ? .caption : .caption2 }
    var buttonFont: Font { isTall ? .body : .subheadline }
    var buttonVerticalPadding: CGFloat { isTall ? 8 : 6 }
    var rowTitleFont: Font { isTall ? .headline : .subheadline.weight(.semibold) }
    var recentRows: Int { isTall ? 4 : 3 }
}

private struct HeroBadge: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.white.opacity(0.14), in: Capsule())
    }
}

private struct StatusPill: View {
    let title: String
    let active: Bool
    let detail: String
    let metrics: LayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(active ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(metrics.captionFont.weight(.semibold))
                    .lineLimit(1)
            }
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, metrics.isTall ? 11 : 9)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PipelineStep: View {
    let icon: String
    let title: String
    let active: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .frame(width: 38, height: 38)
                .foregroundStyle(active ? .white : .secondary)
                .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: Circle())
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(active ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PipelineConnector: View {
    let active: Bool

    var body: some View {
        Rectangle()
            .fill(active ? Color.indigo.opacity(0.55) : Color.secondary.opacity(0.15))
            .frame(height: 2)
            .padding(.bottom, 22)
    }
}

private struct QuickAction: View {
    let title: String
    let icon: String
    let tint: Color
    let metrics: LayoutMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(title)
                    .font(metrics.captionFont.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.isTall ? 15 : 12)
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }
}

private struct AppRow: View {
    let app: RbitAppItem
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.systemImage)
                .font(metrics.rowTitleFont)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 13)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(metrics.rowTitleFont)
                    .lineLimit(1)
                Text(app.subtitle)
                    .font(metrics.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(app.status)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.green.opacity(0.10), in: Capsule())
        }
        .padding(.vertical, 5)
    }
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
            .overlay {
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
    }
}
