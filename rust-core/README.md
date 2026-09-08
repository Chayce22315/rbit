# rbit pairing core

this folder contains the small rust ffi layer used by rbit for ios 27 wireless remote pairing.

it links the pinned `jkcoxson/idevice` remote-pairing implementation rather than reimplementing the cryptography or wire protocol in swift.

build locally with:

```sh
./rust-core/build-rust.sh device
```

for simulator builds:

```sh
./rust-core/build-rust.sh simulator
```

pairing is device-dependent and requires ios 27 developer mode plus local network access. the core intentionally reports errors instead of manufacturing a success state.
