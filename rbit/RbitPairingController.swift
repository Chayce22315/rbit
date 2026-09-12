import Foundation
import Network
import Darwin

@MainActor
final class RbitPairingController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingLocalNetwork
        case waitingForDevice
        case showPin(String)
        case paired
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var serviceName: String?

    private static let serviceType = "_remotepairing-pairable-host._tcp."

    private var service: BonjourPairingPublisher?
    private var serviceNameStorage: String?
    private var serviceTXT: [String: Data] = [:]
    private var servicePort: UInt16 = 0
    private var task: Task<Void, Never>?

    func startForegroundPairing() {
        task?.cancel()
        service?.stop()
        service = nil
        phase = .waitingForDevice
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        service?.stop()
        service = nil
        phase = .idle
    }

    private func run() async {
        // Existing pairing host implementation is invoked by the repository's bridge.
        // The host publishes its actual TCP port and TXT metadata through the ready callback.
        // Keep that protocol unchanged here and advertise the port with DNS-SD.
        let context = Unmanaged.passRetained(PairingCallbackContext(controller: self))
        defer { context.release() }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("rbit-pairing.plist")
        let contextPointer = context.toOpaque()

        let callbackReady: RbitReadyCallback = { rawContext, identifier, port, txtKeys, txtValues, count in
            guard let rawContext else { return }
            let callbackContext = Unmanaged<PairingCallbackContext>.fromOpaque(rawContext).takeUnretainedValue()
            var txt: [String: Data] = [:]
            if count > 0, let txtKeys, let txtValues {
                for index in 0..<count {
                    guard let keyPointer = txtKeys[index], let valuePointer = txtValues[index] else { continue }
                    txt[String(cString: keyPointer)] = Data(bytes: valuePointer, count: strlen(valuePointer))
                }
            }
            let name = identifier.map(String.init(cString:)) ?? "rbit"
            Task { @MainActor in
                callbackContext.controller.publishPairingService(name: name, port: port, txt: txt)
            }
        }

        let callbackPin: RbitPinCallback = { rawContext, pinPointer in
            guard let rawContext, let pinPointer else { return }
            let callbackContext = Unmanaged<PairingCallbackContext>.fromOpaque(rawContext).takeUnretainedValue()
            let pin = String(cString: pinPointer)
            Task { @MainActor in
                callbackContext.controller.phase = .showPin(pin)
            }
        }

        let call = await Task.detached(priority: .userInitiated) {
            RbitPairingBridge.shared.runHost(
                name: "rbit",
                model: "Mac17,7",
                outputPath: outputURL.path,
                context: contextPointer,
                ready: callbackReady,
                pin: callbackPin
            )
        }.value

        if Task.isCancelled { return }
        if call.status != 0 {
            let message = RbitPairingBridge.shared.string(call.result.error) ?? "pairing host failed with status \(call.status)"
            phase = .failed(message)
            var result = call.result
            RbitPairingBridge.shared.free(&result)
            return
        }

        var result = call.result
        RbitPairingBridge.shared.free(&result)
        service?.stop()
        service = nil
        phase = .paired
    }

    private func publishPairingService(name: String, port: UInt16, txt: [String: Data]) {
        service?.stop()
        serviceNameStorage = name
        serviceTXT = txt
        servicePort = port
        serviceName = name
        phase = .waitingForDevice

        let publisher = BonjourPairingPublisher(
            name: name,
            type: Self.serviceType,
            port: port,
            txt: txt,
            onPublished: { [weak self] publishedName in
                guard let self else { return }
                Task { @MainActor in
                    self.serviceName = publishedName
                    self.phase = .waitingForDevice
                }
            },
            onFailed: { [weak self] message in
                guard let self else { return }
                Task { @MainActor in
                    self.phase = .failed(message)
                }
            }
        )
        service = publisher
        publisher.start()
    }

    private final class PairingCallbackContext: @unchecked Sendable {
        weak var controller: RbitPairingController?
        init(controller: RbitPairingController) {
            self.controller = controller
        }
    }
}

private final class BonjourPairingPublisher: @unchecked Sendable {
    let name: String
    let type: String
    let port: UInt16
    let txt: [String: Data]
    let onPublished: @Sendable (String) -> Void
    let onFailed: @Sendable (String) -> Void

    private let queue = DispatchQueue(label: "com.pixelated.rbit.bonjour")
    private var serviceRef: DNSServiceRef?
    private var started = false

    init(
        name: String,
        type: String,
        port: UInt16,
        txt: [String: Data],
        onPublished: @escaping @Sendable (String) -> Void,
        onFailed: @escaping @Sendable (String) -> Void
    ) {
        self.name = name
        self.type = type
        self.port = port
        self.txt = txt
        self.onPublished = onPublished
        self.onFailed = onFailed
    }

    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true

            let txtData = Self.makeTXTRecord(txt)
            var reference: DNSServiceRef?
            let result = txtData.withUnsafeBytes { txtBytes in
                name.withCString { namePointer in
                    type.withCString { typePointer in
                        DNSServiceRegister(
                            &reference,
                            0,
                            0,
                            namePointer,
                            typePointer,
                            "local.".withCString { $0 },
                            nil,
                            port.bigEndian,
                            UInt16(txtBytes.count),
                            txtBytes.baseAddress,
                            Self.registrationCallback,
                            Unmanaged.passUnretained(self).toOpaque()
                        )
                    }
                }
            }

            guard result == kDNSServiceErr_NoError, let reference else {
                started = false
                onFailed("Bonjour registration failed with error \(Int32(result))")
                return
            }

            serviceRef = reference
            let queueError = DNSServiceSetDispatchQueue(reference, queue)
            guard queueError == kDNSServiceErr_NoError else {
                DNSServiceRefDeallocate(reference)
                serviceRef = nil
                started = false
                onFailed("DNSServiceSetDispatchQueue failed with error \(Int32(queueError))")
                return
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            started = false
            if let reference = serviceRef {
                DNSServiceRefDeallocate(reference)
                serviceRef = nil
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
            publisher.onFailed("Bonjour registration failed with error \(Int32(errorCode))")
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
