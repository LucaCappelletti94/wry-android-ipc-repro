# wry Android: the first IPC call is refused as `about:blank`

[![wry PR](https://img.shields.io/badge/tauri--apps%2Fwry-%231891-blue)](https://github.com/tauri-apps/wry/pull/1891)
[![Tauri](https://img.shields.io/badge/tauri-2.12.4-24c8db)](https://crates.io/crates/tauri/2.12.4)
[![Android](https://img.shields.io/badge/Android-API%2035-3ddc84)](https://developer.android.com/about/versions/15)

Reproducer for [tauri-apps/wry#1891](https://github.com/tauri-apps/wry/pull/1891). It is a stock Tauri 2.12.4 app with the default `tauri.localhost` frontend and the `core:default` capability, whose page calls `event.listen` from its first inline script. When the main thread is busy as the page loads, the call is refused:

```
event.listen not allowed on window "main", webview "main", URL: about:blank
```

## Run

Requires the [Tauri Android prerequisites](https://tauri.app/start/prerequisites/#android) and one emulator or device.

```sh
ANDROID_SERIAL=emulator-5554 ./repro.sh baseline   # wry dev at 6642074, the PR's merge base
ANDROID_SERIAL=emulator-5554 ./repro.sh pr         # the PR head, 2acf32e
```

Optional arguments are `runs` (10), `stall_ms` (3000) and `slice_ms` (100). `stall_ms` 0 is the control. The build targets `x86_64`. Set `TARGET=aarch64` for a phone.

## The busy main thread

`stall.toml` uses wry's `WRY_IPC_CLASS_EXTENSION` hook to keep the main thread busy in short slices from webview creation. The navigation advances between slices, while the posted `onPageStarted` callback, the only writer of the `currentUrl` that `Ipc.postMessage` sends, waits behind the next slice. One long block does not reproduce it, because it also holds back the navigation commit.

## Results

Android 15 x86_64 emulator, WebView 124.0.6367.219, cold start per run.

| wry | busy main thread | result |
|---|---|---|
| baseline | 3000 ms in 100 ms slices | 30 of 30 refused |
| baseline | 3000 ms in 50 ms slices | 10 of 10 refused |
| baseline | 1500 ms in 100 ms slices | 10 of 10 refused |
| baseline | none | 10 of 10 allowed |
| PR | 3000 ms in 100 ms slices | 30 of 30 allowed |
| PR | 3000 ms in 50 ms slices | 10 of 10 allowed |
| PR | 1500 ms in 100 ms slices | 10 of 10 allowed |
| PR | none | 10 of 10 allowed |
