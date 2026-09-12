import BackgroundTasks
import Combine
import Foundation
import Network
import dnssd

@MainActor
final class RbitPairingController: ObservableObject {
    static let shared = RbitPairingController()
    static let taskIdentifierBase = "com.chayce22315.rbit.continuedProcessing.pairing"
    static let permittedTaskIdentifier = "com.chayce22315.rbit.continuedProcessing.pairing.*"
    static let serviceType = "_remotepairing-pairable-host._tcp."

    enum Phase: Equatable {
        case idle
        case requestingNetwork
        case waitingForDevice
        case showPin(String)
        case paired(name: String, model: String, udid: String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pairingFileURL: URL?
    @Published private(set) var serviceName: String?

    private var servicePublisher: BonjourPairingPublisher?
    private var backgroundTask: BGContinuedProcessingTask?
    private var permissionBrowser: NWBrowser?
    private var workerStarted = false

    private init() {}

    var isRunning: Bool {
        switch phase {
        case .requestingNetwork, .waitingForDevice, .showPin:
            return true
        default:
            return false
        }
    }

    func registerBackgroundTask() {
        // pairing deliberately starts in the foreground. ios may reject a
        // continued-processing request depending on entitlements/device state.
    }

    func start() {
        guard !isRunning else { return }
        workerStarted = false
        pairingFileURL = nil
        serviceName = nil
        phase = .requestingNetwork
        requestLocalNetworkAndContinue()
    }

    func cancel() {
        permissionBrowser?.cancel()
        permissionBrowser = nil
        backgroundTask?.setTaskCompleted(success: false)
        backgroundTask = nil
        servicePublisher?.stop()
        servicePublisher = nil
        workerStarted = false
        phase = .idle
    }

    private func requestLocalNetworkAndContinue() {
        permissionBrowser?.cancel()

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: .tcp
        )
        permissionBrowser = browser

        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self else { return }

            Task { @MainActor in
                switch state {
                case .ready:
                    guard self.permissionBrowser === browser else { return }
                    self.permissionBrowser?.cancel()
                    self.permissionBrowser = nil
                    self.startForegroundPairing()

                case .waiting(let error), .failed(let error):
                    self.permissionBrowser?.cancel()
                    self.permissionBrowser = nil
                    if Self.isLocalNetworkDenied(error) {
                        self.phase = .failed(
                            "rbit cannot access the local network. allow rbit in Settings › Privacy & Security › Local Network, then try again."
                        )
                    } else {
                        self.phase = .failed(
                            "could not access the local network: \(error.localizedDescription)"
                        )
                    }

                case .cancelled:
                    if self.phase == .requestingNetwork {
                        self.permissionBrowser = nil
                    }

                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)
    }

    private static func isLocalNetworkDenied(_ error: NWError) -> Bool {
        switch error {
        case .dns(let code):
            return Int32(code) == kDNSServiceErr_PolicyDenied
        case .posix(let code):
            return code.rawValue == EACCES
        default:
            return error.localizedDescription.localizedCaseInsensitiveContains("noauth")
                || error.localizedDescription.localizedCaseInsensitiveContains("permission")
                || error.localizedDescription.localizedCaseInsensitiveContains("denied")
        }
    }

    private func startForegroundPairing() {
        phase = .waitingForDevice
        run(task: nil)
    }

    private func run(task: BGContinuedProcessingTask?) {
        guard !workerStarted else { return }
        workerStarted = true
        backgroundTask = task
        task?.progress.totalUnitCount = 100
        task?.progress.completedUnitCount = 5
        task?.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.finish(success: false, error: "ios stopped the pairing task before a device connected.")
            }
        }

        let outputURL = makePairingFileURL()
        let context = Unmanaged.passUnretained(self).toOpaque()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let callbackReady: RbitReadyCallback = { context, serviceID, port, keys, values, count in
                guard let context else { return }
                let controller = Unmanaged<RbitPairingController>.fromOpaque(context).takeUnretainedValue()
                let identifier = serviceID.map { String(cString: $0) } ?? "rbit"
                var txt: [String: Data] = [:]
                if let keys, let values {
                    for index in 0..<count {
                        guard let key = keys[index], let value = values[index] else { continue }
                        txt[String(cString: key)] = Data(String(cString: value).utf8)
                    }
                }
                Task { @MainActor in
                    controller.publishPairingService(name: identifier, port: port, txt: txt)
                }
            }

            let callbackPin: RbitPinCallback = { context, pin in
                guard let context, let pin else { return }
                let controller = Unmanaged<RbitPairingController>.fromOpaque(context).takeUnretainedValue()
                let value = String(cString: pin)
                Task { @MainActor in
                    controller.phase = .showPin(value)
                    controller.backgroundTask?.progress.completedUnitCount = 65
                }
            }

            let call = RbitPairingBridge.shared.runHost(
                name: "rbit",
                model: "Mac17,7",
                outputPath: outputURL.path,
                context: UnsafeMutableRawPointer(context),
                ready: callbackReady,
                pin: callbackPin
            )

            let status = call.status
            var result = call.result
            let error = RbitPairingBridge.shared.string(result.error)
            let deviceName = RbitPairingBridge.shared.string(result.deviceName) ?? "iphone"
            let deviceModel = RbitPairingBridge.shared.string(result.deviceModel) ?? "unknown"
            let deviceUDID = RbitPairingBridge.shared.string(result.deviceUDID) ?? "unknown"
            RbitPairingBridge.shared.free(&result)

            Task { @MainActor in
                guard self.workerStarted else { return }
                if status == 0 {
                    self.servicePublisher?.stop()
                    self.servicePublisher = nil
                    self.pairingFileURL = outputURL
                    self.backgroundTask?.progress.completedUnitCount = 100
                    self.finish(success: true, paired: (deviceName, deviceModel, deviceUDID))
                } else {
                    self.finish(success: false, error: error ?? "remote pairing failed")
                }
            }
        }
    }

    private func publishPairingService(name: String, port: UInt16, txt: [String: Data]) {
        servicePublisher?.stop()

        let publisher = BonjourPairingPublisher(
            name: name,
            type: Self.serviceType,
            port: port,
            txt: txt,
            onPublished: { [weak self] publishedName in
                Task { @MainActor in
                    guard let self, self.workerStarted else { return }
                    self.serviceName = publishedName
                    self.phase = .waitingForDevice
                }
            },
            onFailed: { [weak self] error in
                Task { @MainActor in
                    guard let self, self.workerStarted else { return }
                    self.servicePublisher = nil
                    self.finish(success: false, error: "could not advertise rbit for pairing (\(error)).")
                }
            }
        )

        servicePublisher = publisher
        publisher.start()
        phase = .waitingForDevice
    }

    private func makePairingFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rbit", isDirectory: true)
            .appendingPathComponent("pairing", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("rp_pairing_file.plist")
    }

    private func finish(success: Bool, paired: (String, String, String)? = nil, error: String? = nil) {
        permissionBrowser?.cancel()
        permissionBrowser = nil
        workerStarted = false
        backgroundTask?.setTaskCompleted(success: success)
        backgroundTask = nil
        if let paired {
            phase = .paired(name: paired.0, model: paired.1, udid: paired.2)
        } else {
            phase = .failed(error ?? "pairing failed")
        }
    }

    private final class BonjourPairingPublisher: @unchecked Sendable {
        private let name: String
        private let type: String
        private let port: UInt16
        private let txt: [String: Data]
        private let onPublished: (String) -> Void
        private let onFailed: (String) -> Void
        private let queue = DispatchQueue(label: "com.chayce22315.rbit.bonjour-publisher")
        private var serviceRef: DNSServiceRef?
        private var started = false

        init(
            name: String,
            type: String,
            port: UInt16,
            txt: [String: Data],
            onPublished: @escaping (String) -> Void,
            onFailed: @escaping (String) -> Void
        ) {
            self.name = name
            self.type = type
            self.port = port
            self.txt = txt
            self.onPublished = onPublished
            self.onFailed = onFailed
        }

        func start() {
            queue.async { [weak self] in
                guard let self, !self.started else { return }
                self.started = true

                var reference: DNSServiceRef?
                let txtData = Self.makeTXTRecord(self.txt)
                let error: DNSServiceErrorType = txtData.withUnsafeBytes { rawBuffer in
                    self.name.withCString { namePtr in
                        self.type.withCString { typePtr in
                            "local.".withCString { domainPtr in
                                DNSServiceRegister(
                                    &reference,
                                    0,
                                    kDNSServiceInterfaceIndexAny,
                                    namePtr,
                                    typePtr,
                                    domainPtr,
                                    nil,
                                    self.port.bigEndian,
                                    UInt16(txtData.count),
                                    rawBuffer.baseAddress,
                                    Self.registrationCallback,
                                    Unmanaged.passUnretained(self).toOpaque()
                                )
                            }
                        }
                    }
                }

                guard error == kDNSServiceErr_NoError, let reference else {
                    self.started = false
                    self.onFailed("DNSServiceRegister failed with error \(error.rawValue)")
                    return
                }

                self.serviceRef = reference
                let queueError = DNSServiceSetDispatchQueue(reference, self.queue)
                guard queueError == kDNSServiceErr_NoError else {
                    DNSServiceRefDeallocate(reference)
                    self.serviceRef = nil
                    self.started = false
                    self.onFailed("DNSServiceSetDispatchQueue failed with error \(queueError.rawValue)")
                    return
                }
            }
        }

        func stop() {
            queue.async { [weak self] in
                guard let self else { return }
                self.started = false
                if let reference = self.serviceRef {
                    DNSServiceRefDeallocate(reference)
                    self.serviceRef = nil
                }
            }
        }

        private static let registrationCallback: DNSServiceRegisterReply = { _, _, errorCode, name, _, _, context in
            guard let context else { return }
            let publisher = Unmanaged<BonjourPairingPublisher>.fromOpaque(context).takeUnretainedValue()

            if errorCode == kDNSServiceErr_NoError {
                let publishedName = name.map(String.init(cString:)) ?? publisher.name
                publisher.onPublished(publishedName)
            } else {
                publisher.onFailed("Bonjour registration failed with error \(errorCode.rawValue)")
            }
        }

        private static func makeTXTRecord(_ values: [String: Data]) -> Data {
            var record = Data()
            for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                let prefix = Data(key.utf8) + (value.isEmpty ? Data() : Data([0x3d]))
                let entry = prefix + value
                guard !entry.isEmpty, entry.count <= 255 else { continue }
                record.append(UInt8(entry.count))
                record.append(entry)
            }
            if record.isEmpty {
                record.append(0)
            }
            return record
        }
    }
}
