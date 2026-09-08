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
    ) -> RbitPairingResult {
        var result = RbitPairingResult(error: nil, deviceName: nil, deviceModel: nil, deviceUDID: nil, pairingFilePath: nil)
        name.withCString { namePtr in
            model.withCString { modelPtr in
                outputPath.withCString { outputPtr in
                    "0.0.0.0".withCString { bindPtr in
                        _ = rbit_pairing_run_host(bindPtr, 0, namePtr, modelPtr, outputPtr, ready, pin, context, &result)
                    }
                }
            }
        }
        return result
    }

    func freeResult(_ result: UnsafeMutablePointer<RbitPairingResult>) {
        rbit_pairing_result_free(result)
    }
}
