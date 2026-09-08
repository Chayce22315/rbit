import Foundation

typealias RbitReadyCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UInt16,
    UnsafePointer<UnsafePointer<CChar>?>?,
    UnsafePointer<UnsafePointer<CChar>?>?,
    Int
) -> Void

typealias RbitPinCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?
) -> Void

struct RbitPairingResult {
    var error: UnsafeMutablePointer<CChar>?
    var deviceName: UnsafeMutablePointer<CChar>?
    var deviceModel: UnsafeMutablePointer<CChar>?
    var deviceUDID: UnsafeMutablePointer<CChar>?
    var pairingFilePath: UnsafeMutablePointer<CChar>?
}

@_silgen_name("rbit_pairing_run_host")
private func rbit_pairing_run_host(
    _ bindAddress: UnsafePointer<CChar>,
    _ port: UInt16,
    _ name: UnsafePointer<CChar>,
    _ model: UnsafePointer<CChar>,
    _ outputPath: UnsafePointer<CChar>,
    _ ready: RbitReadyCallback?,
    _ pin: RbitPinCallback?,
    _ context: UnsafeMutableRawPointer?,
    _ result: UnsafeMutablePointer<RbitPairingResult>?
) -> Int32

@_silgen_name("rbit_pairing_result_free")
private func rbit_pairing_result_free(_ result: UnsafeMutablePointer<RbitPairingResult>?)

struct RbitPairingCallResult {
    let status: Int32
    var result: RbitPairingResult
}

final class RbitPairingBridge {
    static let shared = RbitPairingBridge()
    private init() {}

    func runHost(
        name: String,
        model: String,
        outputPath: String,
        context: UnsafeMutableRawPointer?,
        ready: RbitReadyCallback?,
        pin: RbitPinCallback?
    ) -> RbitPairingCallResult {
        var result = RbitPairingResult(error: nil, deviceName: nil, deviceModel: nil, deviceUDID: nil, pairingFilePath: nil)
        let status = name.withCString { namePtr in
            model.withCString { modelPtr in
                outputPath.withCString { outputPtr in
                    "0.0.0.0".withCString { bindPtr in
                        rbit_pairing_run_host(bindPtr, 0, namePtr, modelPtr, outputPtr, ready, pin, context, &result)
                    }
                }
            }
        }
        return RbitPairingCallResult(status: status, result: result)
    }

    func string(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        return String(cString: pointer)
    }

    func free(_ result: inout RbitPairingResult) {
        withUnsafeMutablePointer(to: &result) { pointer in
            rbit_pairing_result_free(pointer)
        }
    }
}
