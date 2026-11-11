# nsg - Nikon Smart GPS

An alternative for Nikon's SnapBridge, which provide GPS location to Z cameras via the bluetooth smart mode (the mode you connect with SnapBridge).

## Why?

I own Z 50 II and Z 8 camera, and I'm living in China. China has a law to forbiden all cameras from having built-in GPS for some reason. A workaround is using SnapBridge to provide GPS locations. However, on my Samsung, it's not stable (often disconnected from camera), and consume a lot of battery.

With my new Z8, I'm thinking maybe I can made my own GPS using the 10 pin connector since it's talking NEMA-0183 at 4800 bps. But sadly the Chinese firmware blocks the GPS setting, so even you have Z9, which has built-in GPS, you can't use it.

So for me, and other Chinese users, SnapBridge is the only way to feed GPS into the camera and geotagging the photo.

## Android

The Android implementation is complete and ready to use. It is based on the reverse engineering from [gkoh/furble](https://github.com/gkoh/furble), and has been verified to work with the Nikon Z7 II (and should support any Z camera with SnapBridge smart-device mode).

It can pair with new cameras and connect to saved ones over Bluetooth, inject real GPS (plus network location) into the camera, run as a low-power foreground service in the background, and automatically recover the SnapBridge device ID so you can switch between this app and SnapBridge without deleting any pairing records.

Full documentation is in [android/README.md](android/README.md) (中文版见 [android/README.zh-CN.md](android/README.zh-CN.md)).

- 中文版：[**使用教程**](android/README.zh-CN.md#%E4%BD%BF%E7%94%A8%E6%95%99%E7%A8%8B)
- English: [**Usage Tutorial**](android/README.md#usage)

This Android section is maintained by [HowenXu](https://github.com/HowenXu).

> **中文版**：安卓端实现已完整可用。它基于 [gkoh/furble](https://github.com/gkoh/furble) 的逆向成果，已在尼康 Z7 II 上验证可用（理论上支持所有带 SnapBridge 智能设备模式的 Z 相机）。它可以配对全新相机并连接已保存的相机，通过蓝牙注入真实 GPS（含网络定位），以后台低功耗前台服务方式持续运行，并能自动恢复 SnapBridge 设备标识，让你在本应用与 SnapBridge 之间切换时无需删除任何配对记录。完整文档见 [android/README.md](android/README.md)（中文版见 [android/README.zh-CN.md](android/README.zh-CN.md)）。
> - 中文版：[**使用教程**](android/README.zh-CN.md#%E4%BD%BF%E7%94%A8%E6%95%99%E7%A8%8B)
> - English: [**Usage Tutorial**](android/README.md#usage)
> - 本 Android 部分由 [HowenXu](https://github.com/HowenXu) 维护。

## iOS

The iOS app provides GPS location from your iPhone to Nikon cameras over Bluetooth smart-device mode. It supports camera pairing, automatic reconnection to saved cameras, GPS sync with background location updates, a map preview, and configurable sending intervals and accuracy thresholds.

The app is distributed as source code. Build, sign, and install it on your own iPhone using Xcode and your Personal Team. See the iOS documentation for setup, signing, permissions, and screenshots:

- 中文版：[**使用教程**](ios/README.zh-CN.md)
- English: [**README**](ios/README.md)

## Kotlin PoC (Linux only, require Bluez)

Apparently Android's BLE and BT stack is not easy to use. Using it as a PoC defeat the purpose of clean code just focusing on the core features. So, as a backend developer, I decide to use whatever I'm comfortable: the good old JVM.

Currently the kotlin PoC can pair new devices (test with Z50II and Z8) and connecting to saved devices. Also can send fake GPS payload to the camera.

TODO: make it more robus? Like auto-reconnect when camera wakes up from idle. Also maybe connecting to multiple BLE devices?

## ESP32 (The final product)

The dedicated hardware runs on the ESP32. The original M5StackS3/CoreS3 idea was ruled out because the ESP32-S3 only supports BLE and does not have Bluetooth Classic, which the Nikon smart-device protocol requires for bonding. The original ESP32 has both BLE and Bluetooth Classic, which is why it is the target platform.

Moved from PlatformIO to [pioarduino](https://github.com/pioarduino/platform-espressif32) because platformio sucks. They stay at old version of arduino-esp32. The pioarduino fixed this.

The code is pretty much finished, it can pair new cameras, talk to a UBlox GNSS module, parse NMEA and send TIME and GEO payload over BLE. It runs on the ESP32 WROOM 32E; see `esp32/README.md` for details.

## Known Camera Quirks

### LCD coordinate display

The Nikon camera LCD shows GPS coordinates in **degrees + decimal minutes**, the same format used by the GPS payload this project's ESP32 device sends to the camera. However, the camera's rendering of the fractional minutes is buggy in some cases.

For example, a fractional minute of `51.002'` is shown on the camera LCD as `51.2'`, not `51.002'`. By contrast, `51.688'` is shown correctly as `51.688'`. The failure is not consistent — it appears to depend on the digits of the fractional part.

The value stored in the photo's EXIF tag is correct in both cases (verified with `exiftool`), so the geotagging is accurate. This is a display-only bug in the Nikon camera firmware, not a bug in this project's encoding. This is confirmed on both Z50II and Z8.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for how to build the project, report bugs, and submit changes. Contributors are listed in [CONTRIBUTORS.md](CONTRIBUTORS.md).
