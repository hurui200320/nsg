# nsg - Nikon Smart GPS

An alternative for Nikon's SnapBridge, which provide GPS location to Z cameras.

## Why?

I own Z 50 II and Z 8 camera, and I'm living in China. China has a law to forbiden all cameras from having built-in GPS for some reason. However, a walkaround is using SnapBridge to provide GPS locations. However, on my Samsung, it's not stable (often disconnected from camera), and consume a lot of battery.

With my new Z8, I'm thinking maybe I can made my own GPS using the 10 pin connector since it's talking NEMA-0183 at 4800 bps. But sadly the Chinese firmware blocks the GPS setting, so even you have Z9, which has built-in GPS, you can't use it.

So for me, and other Chinese users, SnapBridge is the only way to feed GPS into the camera and geotagging the photo.

## Android PoC

This project steals the reverse engineer result from [gkoh/furble](https://github.com/gkoh/furble). Initially I thought I have to go through the SnapBridge APK and capture the bluetooth package, but thankfully the community has already done that.

To first proof things works, I build an Android APP for testing. Once finished and verified things works, I'll buy a M5StackS3 and built a dedicated hardware for it, because again, my samsung phone doesn't have a big battery.
