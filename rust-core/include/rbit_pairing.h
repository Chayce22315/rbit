#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*rbit_pairing_ready_cb)(void *ctx,
                                       const char *service_id,
                                       uint16_t port,
                                       const char *const *txt_keys,
                                       const char *const *txt_values,
                                       size_t txt_count);

typedef void (*rbit_pairing_pin_cb)(void *ctx, const char *pin);

typedef struct {
    char *error;
    char *device_name;
    char *device_model;
    char *device_udid;
    char *pairing_file_path;
} rbit_pairing_result;

int32_t rbit_pairing_run_host(const char *bind_addr,
                              uint16_t port,
                              const char *name,
                              const char *model,
                              const char *output_path,
                              rbit_pairing_ready_cb ready_cb,
                              rbit_pairing_pin_cb pin_cb,
                              void *ctx,
                              rbit_pairing_result *out);

void rbit_pairing_result_free(rbit_pairing_result *result);

#ifdef __cplusplus
}
#endif
