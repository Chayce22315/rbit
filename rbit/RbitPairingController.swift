import BackgroundTasks
import Combine
import Foundation
import Network

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

    private var service: NetService?
    private var serviceDelegate: PairingServiceDelegate?
    private var backgroundTask: BGContinuedProcessingTask?
    private var activeTaskIdentifier: String?
    private var workerStarted = false
    private var permissionBrowser: NWBrowser?

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
        // continued processing tasks use a wildcard-permitted identifier and
        // register their concrete, unique identifier when the user starts work.
    }

    func start() {
        guard !isRunning else { return }
        workerStarted = false
        pairingFileURL = nil
        phase = .requestingNetwork
        requestLocalNetworkAndContinue()
    }

    func cancel() {
        permissionBrowser?.cancel()
        permissionBrowser = nil
        backgroundTask?.setTaskCompleted(success: false)
        backgroundTask = nil
        activeTaskIdentifier = nil
        service?.stop()
        service = nil
        serviceDelegate = nil
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
                    await self.submitBackgroundTask()

                case .waiting(let error):
                    if Self.isLocalNetworkDenied(error) {
                        self.permissionBrowser?.cancel()
                        self.permissionBrowser = nil
                        self.phase = .failed(
                            "rbit cannot access the local network. allow rbit in Settings › Privacy & Security › Local Network, then try again."
                        )
                    }

                case .failed(let error):
                    self.permissionBrowser?.cancel()
                    self.permissionBrowser = nil
                    self.phase = .failed(
                        "could not access the local network: \(error.localizedDescription)"
                    )

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
        guard case .dns(let code) = error else { return false }
        return Int(code) == kDNSServiceErr_PolicyDenied
    }

    private func submitBackgroundTask() async {
        phase = .waitingForDevice

        let identifier = "\(Self.taskIdentifierBase).\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        activeTaskIdentifier = identifier

        // ios 26+ continued-processing tasks with a wildcard plist entry must
        // register the fully expanded identifier when the user starts the task.
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: .main
        ) { [weak self] task in
            guard let self, let task = task as? BGContinuedProcessingTask else { return }
            Task { @MainActor in
                self.run(task: task)
            }
        }

        guard registered else {
            // Pairing is still useful while rbit remains foregrounded. Fall back
            // to the real rust pairing host instead of turning a scheduler issue
            // into a pairing failure.
            run(task: nil)
            return
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "rbit pairing",
            subtitle: "waiting for a device"
        )
        request.strategy = .queue

        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } catch {
            // The foreground fallback keeps the actual rppairing handshake alive
            // even when the scheduler refuses to launch a continued task.
            run(task: nil)
        }
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
        let contextBits = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())

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

            let context = UnsafeMutableRawPointer(bitPattern: contextBits)
            let call = RbitPairingBridge.shared.runHost(
                name: "rbit",
                model: "Mac17,7",
                outputPath: outputURL.path,
                context: context,
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
                    self.service?.stop()
                    self.service = nil
                    self.serviceDelegate = nil
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
        service?.stop()
        let netService = NetService(domain: "local.", type: Self.serviceType, name: name, port: Int32(port))
        netService.setTXTRecord(NetService.data(fromTXTRecord: txt))
        let delegate = PairingServiceDelegate(controller: self)
        netService.delegate = delegate
        serviceDelegate = delegate
        netService.publish()
        service = netService
        serviceName = name
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
        activeTaskIdentifier = nil
        if let paired {
            phase = .paired(name: paired.0, model: paired.1, udid: paired.2)
        } else {
            phase = .failed(error ?? "pairing failed")
        }
    }

    private final class PairingServiceDelegate: NSObject, NetServiceDelegate {
        weak var controller: RbitPairingController?
        init(controller: RbitPairingController) { self.controller = controller }

        func netServiceDidPublish(_ sender: NetService) {
            Task { @MainActor [weak controller] in
                controller?.phase = .waitingForDevice
            }
        }

        func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
            Task { @MainActor [weak controller] in
                controller?.phase = .failed("could not advertise rbit for pairing (\(errorDict)).")
            }
        }
    }
}
