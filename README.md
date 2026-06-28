# nsg - Nikon Smart GPS

An alternative for Nikon's SnapBridge, which provide GPS location to Z cameras via the bluetooth smart mode (the mode you connect with SnapBridge).

## Why?

I own Z 50 II and Z 8 camera, and I'm living in China. China has a law to forbiden all cameras from having built-in GPS for some reason. However, a workaround is using SnapBridge to provide GPS locations. However, on my Samsung, it's not stable (often disconnected from camera), and consume a lot of battery.

With my new Z8, I'm thinking maybe I can made my own GPS using the 10 pin connector since it's talking NEMA-0183 at 4800 bps. But sadly the Chinese firmware blocks the GPS setting, so even you have Z9, which has built-in GPS, you can't use it.

So for me, and other Chinese users, SnapBridge is the only way to feed GPS into the camera and geotagging the photo.

## Android PoC

This project steals the reverse engineer result from [gkoh/furble](https://github.com/gkoh/furble). Initially I thought I have to go through the SnapBridge APK and capture the bluetooth package, but thankfully the community has already done that.

The Android PoC has been verified to work with both the Nikon Z50 II and Nikon Z8 over Bluetooth smart-device mode.

To first proof things works, I build an Android APP for testing. Once finished and verified things works, I'll buy a M5StackS3 and built a dedicated hardware for it, because again, my samsung phone doesn't have a big battery.

## Kotlin PoC

Apparently Android's BLE and BT stack is not easy to use. Using it as a PoC defeat the purpose of clean code just focusing on the core features. So, as a backend developer, I decide to use whatever I'm comfortable: the good old JVM.

Currently the kotlin PoC can pair new devices (test with Z50II and Z8) and connecting to saved devices. Also can send fake GPS payload to the camera.

TODO: make it more robus? Like auto-reconnect when camera wakes up from idle. Also maybe connecting to multiple BLE devices?

## M5Stack Core 2

The current plan is to use an M5Stack Core2 as the dedicated hardware. The original M5StackS3/CoreS3 idea was ruled out because the ESP32-S3 only supports BLE and does not have Bluetooth Classic, which the Nikon smart-device protocol requires for bonding. The Core2 uses the original ESP32, which has both BLE and Bluetooth Classic.

Moved from PlatformIO to [pioarduino](https://github.com/pioarduino/platform-espressif32) because platformio sucks. They stay at old version of arduino-esp32. The pioarduino fixed this.
