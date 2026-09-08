use std::ffi::{c_char, c_void, CStr, CString};
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::ptr;
use tokio::net::TcpListener;

use idevice::remote_pairing::{PairableHost, PairableHostInfo, RpPairingFile, RpPairingSocket};

pub type RbitReadyCallback = Option<extern "C" fn(
    ctx: *mut c_void,
    service_id: *const c_char,
    port: u16,
    txt_keys: *const *const c_char,
    txt_values: *const *const c_char,
    txt_count: usize,
)>;

pub type RbitPinCallback = Option<extern "C" fn(ctx: *mut c_void, pin: *const c_char)>;

#[repr(C)]
pub struct RbitPairingResult {
    pub error: *mut c_char,
    pub device_name: *mut c_char,
    pub device_model: *mut c_char,
    pub device_udid: *mut c_char,
    pub pairing_file_path: *mut c_char,
}

impl RbitPairingResult {
    fn empty() -> Self {
        Self {
            error: ptr::null_mut(),
            device_name: ptr::null_mut(),
            device_model: ptr::null_mut(),
            device_udid: ptr::null_mut(),
            pairing_file_path: ptr::null_mut(),
        }
    }
}

fn into_c_string(value: impl Into<Vec<u8>>) -> *mut c_char {
    CString::new(value).unwrap_or_default().into_raw()
}

unsafe fn read_c_string(value: *const c_char, fallback: &str) -> String {
    if value.is_null() {
        return fallback.to_owned();
    }
    CStr::from_ptr(value).to_str().unwrap_or(fallback).to_owned()
}

struct CallbackState {
    ready: RbitReadyCallback,
    pin: RbitPinCallback,
    ctx: *mut c_void,
}

unsafe impl Send for CallbackState {}

#[no_mangle]
pub unsafe extern "C" fn rbit_pairing_run_host(
    bind_addr: *const c_char,
    port: u16,
    name: *const c_char,
    model: *const c_char,
    output_path: *const c_char,
    ready_cb: RbitReadyCallback,
    pin_cb: RbitPinCallback,
    ctx: *mut c_void,
    out: *mut RbitPairingResult,
) -> i32 {
    if out.is_null() {
        return 2;
    }
    *out = RbitPairingResult::empty();

    let bind = read_c_string(bind_addr, "0.0.0.0");
    let host_name = read_c_string(name, "rbit");
    let host_model = read_c_string(model, "Mac17,7");
    let output = read_c_string(output_path, "rp_pairing_file.plist");
    let callbacks = CallbackState {
        ready: ready_cb,
        pin: pin_cb,
        ctx,
    };

    let runtime = match tokio::runtime::Builder::new_multi_thread().enable_all().build() {
        Ok(runtime) => runtime,
        Err(error) => {
            (*out).error = into_c_string(format!("failed to start rust runtime: {error}"));
            return 1;
        }
    };

    match runtime.block_on(pair_host(bind, host_name, host_model, output, port, callbacks)) {
        Ok(result) => {
            (*out).device_name = into_c_string(result.0);
            (*out).device_model = into_c_string(result.1);
            (*out).device_udid = into_c_string(result.2);
            (*out).pairing_file_path = into_c_string(result.3);
            0
        }
        Err(error) => {
            (*out).error = into_c_string(error);
            1
        }
    }
}

async fn pair_host(
    bind: String,
    host_name: String,
    host_model: String,
    output: String,
    port: u16,
    callbacks: CallbackState,
) -> Result<(String, String, String, String), String> {
    let ip = bind.parse::<IpAddr>().unwrap_or(IpAddr::V4(Ipv4Addr::UNSPECIFIED));
    let listener = TcpListener::bind(SocketAddr::new(ip, port))
        .await
        .map_err(|error| format!("failed to bind pairing listener: {error}"))?;
    let actual_port = listener
        .local_addr()
        .map_err(|error| format!("failed to read pairing port: {error}"))?
        .port();

    let pairing_file = RpPairingFile::generate(&host_name);
    let host_info = PairableHostInfo::generate(&host_name, &host_model);
    let service_id = pairing_file.identifier.clone();

    publish_metadata(&callbacks, &host_info, &service_id, actual_port);

    let (stream, _) = listener
        .accept()
        .await
        .map_err(|error| format!("failed waiting for iPhone connection: {error}"))?;

    let socket = RpPairingSocket::new_device(stream);
    let mut host = PairableHost::new(socket, host_info);
    let mut pairing_file = pairing_file;

    let peer = host
        .accept(&mut pairing_file, move |pin| {
            let callback = callbacks.pin;
            let context = callbacks.ctx;
            async move {
                if let Some(callback) = callback {
                    if let Ok(value) = CString::new(pin) {
                        callback(context, value.as_ptr());
                    }
                }
            }
        })
        .await
        .map_err(|error| format!("remote pairing failed: {error}"))?;

    pairing_file
        .write_to_file(&output)
        .await
        .map_err(|error| format!("failed to save pairing file: {error}"))?;

    Ok((peer.name, peer.model, peer.remotepairing_udid, output))
}

fn publish_metadata(
    callbacks: &CallbackState,
    host_info: &PairableHostInfo,
    service_id: &str,
    port: u16,
) {
    let Some(callback) = callbacks.ready else { return };
    let records = host_info.mdns_txt_records(service_id);
    let keys: Vec<CString> = records
        .iter()
        .filter_map(|(key, _)| CString::new(key.as_str()).ok())
        .collect();
    let values: Vec<CString> = records
        .iter()
        .filter_map(|(_, value)| CString::new(value.as_str()).ok())
        .collect();
    let key_ptrs: Vec<*const c_char> = keys.iter().map(|value| value.as_c_str().as_ptr()).collect();
    let value_ptrs: Vec<*const c_char> = values.iter().map(|value| value.as_c_str().as_ptr()).collect();
    let Ok(service) = CString::new(service_id) else { return };

    callback(
        callbacks.ctx,
        service.as_ptr(),
        port,
        key_ptrs.as_ptr(),
        value_ptrs.as_ptr(),
        key_ptrs.len(),
    );
}

#[no_mangle]
pub unsafe extern "C" fn rbit_pairing_result_free(result: *mut RbitPairingResult) {
    if result.is_null() {
        return;
    }
    for value in [
        (*result).error,
        (*result).device_name,
        (*result).device_model,
        (*result).device_udid,
        (*result).pairing_file_path,
    ] {
        if !value.is_null() {
            drop(CString::from_raw(value));
        }
    }
    *result = RbitPairingResult::empty();
}
