# NSG for iOS

NSG for iOS is distributed as source code. Use your Personal Team in Xcode to build, sign, and install the app on your own iPhone.

The project uses Automatic Signing and reads the Team ID and Bundle ID from `Config/Local.xcconfig`. Keep your personal values in that file rather than entering them directly in the project's Signing & Capabilities settings.

IIf you configure signing directly in Xcode's Signing & Capabilities settings, Xcode may save your Team ID and Bundle ID in `project.pbxproj`, which is not excluded by `.gitignore`, so **DO NOT** commit these changes to the cloud for your personal privacy security.

## Initial setup

Run the following command from the repository's root directory:

```sh
cd ios
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Set these two values in `Config/Local.xcconfig`:

- `NSG_APP_BUNDLE_ID`: Your unique application identifier in reverse-DNS format.
- `NSG_SIGNING_TEAM`: The Team ID associated with your signed-in Xcode account, not your Apple Account email address or team display name.

### How to find your Personal Team ID?

If you do not have a local development certificate yet, create one in Xcode:

1. Open Xcode > Settings > Apple Accounts and sign in to your Apple Account.
2. Select your account, then open your Personal Team.
3. Click Manage Certificates.
4. Click the Add (+) button and choose Apple Development.

Then run the following cammand in Terminal:

```sh
/usr/bin/security find-certificate -a -c "Apple Development" -p |
awk '
/-----BEGIN CERTIFICATE-----/ { certificate = "" }
{ certificate = certificate $0 "\n" }
/-----END CERTIFICATE-----/ {
    command = "/usr/bin/openssl x509 -noout -subject -dates -nameopt sep_multiline"
    print certificate | command
    close(command)
}'
```

Look for the `OU` (Organizational Unit) field in the output and set `NSG_SIGNING_TEAM` in `Config/Local.xcconfig` to the actual value shown for your certificate. For example:

```text
OU=ABCDE12345
```

## Build and install

1. Complete the initial setup above and replace both example values in `Config/Local.xcconfig` with your own Bundle ID and Team ID.
2. Open `ios/NSG.xcodeproj` in Xcode and select the `NSG` scheme.
3. Connect your iPhone to your Mac, unlock it, and accept any pairing or Trust This Computer prompts.
4. On your iPhone, open Settings > Privacy & Security > Developer Mode. Enable it, restart when prompted, and confirm after restarting. See Apple's [Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
5. Select your iPhone as the run destination in Xcode's toolbar.
6. Choose Product > Run (`Command-R`). Xcode will build, sign, install, and launch NSG on your iPhone. Initial signing requires an internet connection; complete any account authentication or Keychain access prompts.

> **Note:** Personal Team provisioning profiles expire after 7 days. Rebuild and reinstall the app from Xcode when the profile expires. You do not need to recreate the development certificate or look up your Team ID again just because a provisioning profile expired. See Apple's [Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account#enable-a-personal-team-in-xcode).

## Permissions and background configuration

The app target declares the following purposes, which are included in the generated `Info.plist` at build time:

- `NSBluetoothAlwaysUsageDescription`: Discover, pair with, and connect to Nikon cameras, and send your phone's GPS location.
- `NSLocationWhenInUseUsageDescription`: Access your location while using the app and send it to the camera.
- `NSLocationAlwaysAndWhenInUseUsageDescription`: Continue providing location updates to the camera while using other apps or locking the phone, once location sync is enabled.
- `UIBackgroundModes`: `bluetooth-central` and `location`, configured for future background Bluetooth communication and location updates.

> The app is currently a UI scaffold. These declarations do not automatically request permission or mean that Bluetooth connections, GPS sync, or background operation have been implemented.

## Issues

If you encounter problems building, signing, or using NSG for iOS, please open an issue. Read [CONTRIBUTING.md](../CONTRIBUTING.md) first.

## References

- [Apple: Adding a build configuration file to your project](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project)
- [Apple: Developer memberships and free development limits](https://developer.apple.com/support/compare-memberships/)
