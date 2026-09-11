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
            let metrics = LayoutMetrics(size: proxy.size)
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
            if case .paired = phase { store.pairingState = .paired }
        }
    }

    private func home(metrics: LayoutMetrics) -> some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: metrics.sectionSpacing) {
                    hero(metrics)
                    if metrics.isRegularWidth {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: metrics.sectionSpacing) {
                                statusCard(metrics)
                                installCard(metrics)
                            }
                            VStack(spacing: metrics.sectionSpacing) {
                                statusCard(metrics)
                                installCard(metrics)
                            }
                        }
                        overviewCard(metrics)
                        quickActions(metrics)
                        recentCard(metrics)
                    } else {
                        statusCard(metrics)
                        installCard(metrics)
                        overviewCard(metrics)
                        quickActions(metrics)
                        recentCard(metrics)
                    }
                }
                .frame(maxWidth: metrics.contentMaxWidth)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(maxWidth: .infinity)
            }
            .background(RbitBackground().ignoresSafeArea())
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
            LinearGradient(
                colors: [.indigo, .purple, .blue, .cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle().fill(.white.opacity(0.18)).frame(width: 190, height: 190).offset(x: metrics.heroOrbOffset, y: -55)
            Circle().fill(.white.opacity(0.10)).frame(width: 120, height: 120).offset(x: metrics.heroOrbOffset + 90, y: 45)
            Image(systemName: "sparkles")
                .font(.system(size: metrics.isRegularWidth ? 58 : 42, weight: .black))
                .foregroundStyle(.white.opacity(0.18))
                .offset(x: metrics.heroOrbOffset - 25, y: -15)
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.down.app.fill").font(.title2.bold())
                    Text("rbit").font(metrics.titleFont.bold())
                }
                Text("research • brainstorm • implement • try again")
                    .font(metrics.captionFont.weight(.medium)).opacity(0.92)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    HeroBadge(title: vpn.connected ? "vpn ready" : "vpn offline", icon: vpn.connected ? "checkmark" : "xmark")
                    HeroBadge(title: pairing.isRunning ? "pairing" : (store.pairingState == .paired ? "paired" : "ready"), icon: pairing.isRunning ? "antenna.radiowaves.left.and.right" : "iphone.gen3")
                }
            }
            .foregroundStyle(.white)
            .padding(metrics.heroPadding)
        }
        .frame(height: metrics.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        .shadow(color: .indigo.opacity(0.22), radius: 22, y: 10)
    }

    private func statusCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack {
                Label("device status", systemImage: "iphone.gen3").font(metrics.headingFont)
                Spacer()
                Circle().fill(vpn.connected ? .green : .orange).frame(width: 9, height: 9)
            }
            HStack(spacing: 9) {
                StatusPill(title: "localdevvpn", active: vpn.connected, detail: vpn.interfaceName ?? "not detected", tint: .cyan, metrics: metrics)
                StatusPill(title: "pairing", active: store.pairingState == .paired, detail: store.pairingState.rawValue, tint: .purple, metrics: metrics)
                StatusPill(title: "apple id", active: store.appleAccountConnected, detail: store.appleAccountConnected ? "connected" : "not connected", tint: .blue, metrics: metrics)
            }
            Button { showingPairing = true } label: {
                Label(store.pairingState == .paired ? "manage pairing" : "pair this iphone", systemImage: store.pairingState == .paired ? "checkmark.circle.fill" : "link")
                    .font(metrics.buttonFont.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, metrics.buttonVerticalPadding)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .cardStyle(metrics, tint: .indigo)
    }

    private func installCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("install an ipa", systemImage: "shippingbox.fill").font(metrics.headingFont)
                    Text("keep imported apps on-device and ready for the signing pipeline.")
                        .font(metrics.bodyFont).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text("\(store.importedApps.count)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.purple.opacity(0.10), in: Capsule())
            }
            Button { showingImporter = true } label: {
                Label("add ipa", systemImage: "plus")
                    .font(metrics.buttonFont.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, metrics.buttonVerticalPadding)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .cardStyle(metrics, tint: .purple)
    }

    private func overviewCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("pipeline").font(metrics.headingFont)
            HStack(spacing: 0) {
                PipelineStep(icon: "doc.badge.plus", title: "import", active: !store.importedApps.isEmpty, tint: .cyan)
                PipelineConnector(active: !store.importedApps.isEmpty)
                PipelineStep(icon: "signature", title: "sign", active: false, tint: .purple)
                PipelineConnector(active: false)
                PipelineStep(icon: "iphone.gen3", title: "install", active: false, tint: .blue)
            }
            Text("import is ready. signing and device installation are the next pipeline stages.")
                .font(metrics.captionFont).foregroundStyle(.secondary)
        }
        .cardStyle(metrics, tint: .cyan)
    }

    private func quickActions(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("quick actions").font(metrics.headingFont)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.quickActionMinimum), spacing: metrics.cardSpacing)], spacing: metrics.cardSpacing) {
                QuickAction(title: "pair", icon: "link", tint: .indigo, metrics: metrics) { showingPairing = true }
                QuickAction(title: "apps", icon: "square.grid.2x2.fill", tint: .purple, metrics: metrics) { selectedTab = 1 }
                QuickAction(title: "activity", icon: "clock.arrow.circlepath", tint: .blue, metrics: metrics) { selectedTab = 2 }
            }
        }
    }

    private func recentCard(_ metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack {
                Label("recent", systemImage: "sparkles").font(metrics.headingFont)
                Spacer()
                Text("\(store.activity.count)").font(metrics.captionFont.bold().monospacedDigit()).foregroundStyle(.secondary)
            }
            if store.activity.isEmpty {
                Text("nothing has happened yet").font(metrics.bodyFont).foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.activity.prefix(metrics.recentRows).enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: index == 0 ? "bolt.fill" : "checkmark.circle.fill")
                            .foregroundStyle(index == 0 ? Color.indigo : Color.secondary)
                        Text(item).font(metrics.bodyFont).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(metrics, tint: .blue)
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
                        Button("import ipa") { showingImporter = true }.buttonStyle(.borderedProminent).tint(.purple)
                    }
                } else {
                    List {
                        Section {
                            ForEach(store.importedApps) { app in
                                AppRow(app: app, metrics: metrics)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { store.removeApp(app) } label: {
                                            Label("delete", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: { Text("\(store.importedApps.count) imported") }
                    }
                    .scrollContentBackground(.hidden)
                    .background(RbitBackground())
                }
            }
            .navigationTitle("apps")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "plus") }.accessibilityLabel("add ipa")
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
                                    Circle().fill(index == 0 ? Color.indigo.opacity(0.14) : Color.secondary.opacity(0.10))
                                    Image(systemName: index == 0 ? "bolt.fill" : "checkmark")
                                        .font(.caption.bold()).foregroundStyle(index == 0 ? .indigo : .secondary)
                                }
                                .frame(width: 34, height: 34)
                                Text(item).font(metrics.bodyFont).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(RbitBackground())
                }
            }
            .navigationTitle("activity")
        }
    }
}

private struct LayoutMetrics {
    let size: CGSize
    var isRegularWidth: Bool { size.width >= 700 }
    var isCompactHeight: Bool { size.height < 620 }
    var horizontalPadding: CGFloat { isRegularWidth ? 28 : 16 }
    var verticalPadding: CGFloat { isCompactHeight ? 12 : (isRegularWidth ? 28 : 20) }
    var sectionSpacing: CGFloat { isCompactHeight ? 12 : (isRegularWidth ? 20 : 16) }
    var cardSpacing: CGFloat { isCompactHeight ? 9 : 12 }
    var cornerRadius: CGFloat { isRegularWidth ? 28 : 22 }
    var contentMaxWidth: CGFloat { isRegularWidth ? 760 : 600 }
    var titleFont: Font { isRegularWidth ? .largeTitle : .title }
    var headingFont: Font { isCompactHeight ? .subheadline.weight(.semibold) : .headline }
    var bodyFont: Font { isCompactHeight ? .footnote : .subheadline }
    var captionFont: Font { isCompactHeight ? .caption2 : .caption }
    var buttonFont: Font { isCompactHeight ? .subheadline : .body }
    var buttonVerticalPadding: CGFloat { isCompactHeight ? 6 : 9 }
    var rowTitleFont: Font { isCompactHeight ? .subheadline.weight(.semibold) : .headline }
    var recentRows: Int { isCompactHeight ? 2 : (isRegularWidth ? 5 : 4) }
    var heroHeight: CGFloat { isRegularWidth ? 230 : (isCompactHeight ? 148 : 184) }
    var heroPadding: CGFloat { isRegularWidth ? 28 : (isCompactHeight ? 16 : 20) }
    var heroOrbOffset: CGFloat { isRegularWidth ? 430 : 210 }
    var quickActionMinimum: CGFloat { isRegularWidth ? 150 : 90 }
}

private struct RbitBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: [Color.indigo.opacity(0.08), Color.purple.opacity(0.05), Color.cyan.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct HeroBadge: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(0.15), in: Capsule())
    }
}

private struct StatusPill: View {
    let title: String
    let active: Bool
    let detail: String
    let tint: Color
    let metrics: LayoutMetrics
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(active ? tint : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                Text(title).font(metrics.captionFont.weight(.semibold)).lineLimit(1)
            }
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, metrics.isCompactHeight ? 8 : 11)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.12), lineWidth: 1) }
    }
}

private struct PipelineStep: View {
    let icon: String
    let title: String
    let active: Bool
    let tint: Color
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.subheadline.bold()).frame(width: 38, height: 38)
                .foregroundStyle(active ? .white : .secondary)
                .background(active ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: Circle())
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(active ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PipelineConnector: View {
    let active: Bool
    var body: some View {
        Rectangle().fill(active ? Color.indigo.opacity(0.55) : Color.secondary.opacity(0.15))
            .frame(height: 2).padding(.bottom, 22)
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
            HStack(spacing: 9) {
                Image(systemName: icon).font(.headline).foregroundStyle(tint)
                Text(title).font(metrics.captionFont.bold())
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14).padding(.vertical, metrics.isCompactHeight ? 11 : 15)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(tint.opacity(0.13), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

private struct AppRow: View {
    let app: RbitAppItem
    let metrics: LayoutMetrics
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.systemImage).font(metrics.rowTitleFont).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(LinearGradient(colors: [.indigo, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(metrics.rowTitleFont).lineLimit(1)
                Text(app.subtitle).font(metrics.captionFont).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(app.status).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                .padding(.horizontal, 8).padding(.vertical, 5).background(.green.opacity(0.10), in: Capsule())
        }
        .padding(.vertical, 5)
    }
}

private extension View {
    func cardStyle(_ metrics: LayoutMetrics, tint: Color) -> some View {
        padding(metrics.isCompactHeight ? 13 : (metrics.isRegularWidth ? 20 : 17))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.07), radius: 14, y: 6)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: RbitStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("connection") {
                    LabeledContent("localdevvpn", value: LocalDevVPNMonitor.shared.connected ? "connected" : "not detected")
                    LabeledContent("pairing", value: store.pairingState.rawValue)
                }
                Section("apple account") {
                    Toggle("signed-in account", isOn: $store.appleAccountConnected)
                    Text("credentials will stay on-device when the signing pipeline is connected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("storage") {
                    LabeledContent("imported ipas", value: "\(store.importedApps.count)")
                    Text("imported files are kept in rbit's private application support storage.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("about") {
                    LabeledContent("version", value: "0.3.0")
                    LabeledContent("target", value: "ios 27")
                    LabeledContent("pipeline", value: "local-first")
                }
            }
            .navigationTitle("settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("done") { dismiss() } }
            }
        }
    }
}

#Preview { ContentView() }
