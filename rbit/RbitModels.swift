import Combine
import Foundation

struct RbitAppItem: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let subtitle: String
    let systemImage: String
    let status: String
    let fileName: String
    let importedAt: Date
}

enum RbitPairingState: String, Codable {
    case notPaired = "not paired"
    case pairing = "pairing"
    case paired = "paired"
}

@MainActor
final class RbitStore: ObservableObject {
    @Published var pairingState: RbitPairingState = .notPaired
    @Published var localDevVPNEnabled = false
    @Published var appleAccountConnected = false
    @Published private(set) var importedApps: [RbitAppItem] = []
    @Published private(set) var activity: [String] = ["rbit is ready"]

    private let fileManager = FileManager.default
    private let metadataURL: URL
    private let ipaDirectory: URL

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rbit", isDirectory: true)
        metadataURL = support.appendingPathComponent("apps.json")
        ipaDirectory = support.appendingPathComponent("ipas", isDirectory: true)
        createStorageIfNeeded()
        loadMetadata()
    }

    func addActivity(_ message: String) {
        activity.insert(message, at: 0)
        if activity.count > 100 { activity.removeLast(activity.count - 100) }
    }

    func importIPA(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            try createStorageIfNeeded()
            let sourceName = url.deletingPathExtension().lastPathComponent
            let safeName = sanitizedFileName(url.lastPathComponent)
            let destination = uniqueURL(in: ipaDirectory, named: safeName)
            try fileManager.copyItem(at: url, to: destination)

            let item = RbitAppItem(
                id: UUID(),
                name: sourceName,
                subtitle: "imported ipa",
                systemImage: "shippingbox.fill",
                status: "ready",
                fileName: destination.lastPathComponent,
                importedAt: Date()
            )
            importedApps.insert(item, at: 0)
            saveMetadata()
            addActivity("imported \(sourceName)")
        } catch {
            addActivity("ipa import failed: \(error.localizedDescription)")
        }
    }

    func removeApp(_ app: RbitAppItem) {
        let url = ipaDirectory.appendingPathComponent(app.fileName)
        try? fileManager.removeItem(at: url)
        importedApps.removeAll { $0.id == app.id }
        saveMetadata()
        addActivity("removed \(app.name)")
    }

    func storedIPAURL(for app: RbitAppItem) -> URL {
        ipaDirectory.appendingPathComponent(app.fileName)
    }

    private func createStorageIfNeeded() {
        try? fileManager.createDirectory(at: ipaDirectory, withIntermediateDirectories: true)
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([RbitAppItem].self, from: data) else {
            importedApps = []
            return
        }

        importedApps = decoded.filter { fileManager.fileExists(atPath: ipaDirectory.appendingPathComponent($0.fileName).path) }
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(importedApps) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func uniqueURL(in directory: URL, named name: String) -> URL {
        var candidate = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension
        var index = 2
        repeat {
            let numbered = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private func sanitizedFileName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
    }
}
