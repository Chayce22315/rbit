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
            submitBackgroundTask()
        }
    }

    func cancel() {
        backgroundTask?.setTaskCompleted(success: false)
        backgroundTask = nil
        service?.stop()
        service = nil
        workerStarted = false
        phase = .idle
    }

    private func submitBackgroundTask() {
        phase = .waitingForDevice
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "rbit pairing",
            subtitle: "waiting for this iphone"
        )
        request.strategy = .queue

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            phase = .failed("could not start the continuous pairing task: \(error.localizedDescription)")
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
        let context = Unmanaged.passUnretained(self).toOpaque()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var result = RbitPairingResult(error: nil, deviceName: nil, deviceModel: nil, deviceUDID: nil, pairingFilePath: nil)

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

            let status = RbitPairingBridge.shared.runHost(
                name: "rbit",
                model: "Mac17,7",
                outputPath: outputURL.path,
                context: context,
                ready: callbackReady,
                pin: callbackPin,
                result: &result
            )

            let error = result.error.map { String(cString: $0) }
            let deviceName = result.deviceName.map { String(cString: $0) } ?? "iphone"
            let deviceModel = result.deviceModel.map { String(cString: $0) } ?? "unknown"
            let deviceUDID = result.deviceUDID.map { String(cString: $0) } ?? "unknown"

            rbit_pairing_result_free(&result)

            Task { @MainActor in
                guard self.workerStarted else { return }
                if status == 0 {
                    self.service?.stop()
                    self.service = nil
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
            var finished = false
            browser.stateUpdateHandler = { state in
                guard !finished else { return }
                switch state {
                case .ready, .waiting:
                    finished = true
                    browser.cancel()
                    continuation.resume(returning: true)
                case .failed:
                    finished = true
                    browser.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            browser.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                guard !finished else { return }
                finished = true
                browser.cancel()
                continuation.resume(returning: false)
            }
        }
    }

    private func publishPairingService(name: String, port: UInt16, txt: [String: Data]) {
        service?.stop()
        let netService = NetService(domain: "local.", type: Self.serviceType, name: name, port: Int32(port))
        netService.setTXTRecord(NetService.data(fromTXTRecord: txt))
        netService.delegate = PairingServiceDelegate(controller: self)
        netService.publish()
        service = netService
        serviceName = name
        phase = .waitingForDevice
    }

    private func makePairingFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rbit", isDirectory: true)
            .appendingPathComponent("pairing", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("rp_pairing_file.plist")
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

    private final class PairingServiceDelegate: NSObject, NetServiceDelegate {
        weak var controller: RbitPairingController?
        init(controller: RbitPairingController) { self.controller = controller }
        func netServiceDidPublish(_ sender: NetService) {
            controller?.phase = .waitingForDevice
        }
        func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
            controller?.phase = .failed("could not advertise rbit for pairing (\(errorDict)).")
        }
    }
}
