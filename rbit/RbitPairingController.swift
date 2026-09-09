import BackgroundTasks
import Combine
import Foundation
import Network

@MainActor
final class RbitPairingController: ObservableObject {
    static let shared = RbitPairingController()
    static let taskIdentifier = "com.chayce22315.rbit.continuedProcessing.pairing"
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
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: .main) { task in
            guard let task = task as? BGContinuedProcessingTask else { return }
            Task { @MainActor in
                Self.shared.run(task: task)
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        workerStarted = false
        phase = .requestingNetwork
        pairingFileURL = nil

        Task { @MainActor in
            guard await requestLocalNetwork() else {
                phase = .failed("local network permission is required. enable it in settings and try again.")
                return
            }
            await submitBackgroundTask()
        }
    }

    func cancel() {
        backgroundTask?.setTaskCompleted(success: false)
        backgroundTask = nil
        service?.stop()
        service = nil
        serviceDelegate = nil
        workerStarted = false
        phase = .idle
    }

    private func submitBackgroundTask() async {
        phase = .waitingForDevice
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "rbit pairing",
            subtitle: "waiting for this iphone"
        )
        request.strategy = .queue

        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } catch {
            phase = .failed(
                "could not start the continuous pairing task: \(error.localizedDescription)"
            )
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
        // Raw pointers are passed only to the C callbacks. Store the address as
        // an integer so Swift 6 does not capture a non-Sendable pointer in the
        // worker closure. The controller remains alive for the duration of the
        // pairing worker through the main-actor state.
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

    private func requestLocalNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
            let gate = ContinuationGate()

            browser.stateUpdateHandler = { state in
                switch state {
                case .ready, .waiting:
                    guard gate.claim() else { return }
                    browser.cancel()
                    continuation.resume(returning: true)
                case .failed:
                    guard gate.claim() else { return }
                    browser.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            browser.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                guard gate.claim() else { return }
                browser.cancel()
                continuation.resume(returning: false)
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
        workerStarted = false
        backgroundTask?.setTaskCompleted(success: success)
        backgroundTask = nil
        if let paired {
            phase = .paired(name: paired.0, model: paired.1, udid: paired.2)
        } else {
            phase = .failed(error ?? "pairing failed")
        }
    }

    private final class ContinuationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
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
