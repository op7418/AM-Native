# AM Native

![AM Native mouse button mapping interface](docs/images/am-native-screenshot.jpeg)

[中文](README.md) · **English**

A native macOS settings app for the **Angry Miao AM Infinity .97**. Read battery status, adjust DPI and remap onboard buttons for everyday Mac use.

Built with SwiftUI, AppKit and direct IOKit HID / CoreBluetooth communication. The official settings app does not need to run. The current app interface is in Chinese; this README is the English guide.

## Download and install

**[Download the latest preview for Apple Silicon](https://github.com/op7418/AM-Native/releases/tag/v0.6.0)**

1. Download `AMNative-VERSION-arm64-preview.zip` from the release and unzip it.
2. Drag `AM Native.app` into Applications and open it.
3. Quit the official Angry Miao app/background process and close its mouse settings webpage.
4. Connect over **USB, Bluetooth or the 2.4 GHz receiver** and wake the mouse. For Bluetooth, first pair and connect it in macOS settings, then allow AM Native Bluetooth access when prompted. Wait for the connected status.

### macOS cannot verify the developer

The preview has an **ad-hoc signature only**. It has **no Developer ID signature and is not notarized by Apple**.

After confirming that the download came from this repository's release, try opening it once, then go to **System Settings → Privacy & Security → Open Anyway** and follow the system prompts. See [Apple's instructions](https://support.apple.com/en-us/102445). If that option is unavailable or you see a different error, report it with a screenshot in [Issues](https://github.com/op7418/AM-Native/issues).

### Compatibility

| Requirement | Current status |
| --- | --- |
| Mac | Apple Silicon (M-series); the release does not run on Intel |
| macOS | Declared minimum: 14; tested on macOS 27; macOS 14–26 have not been tested on hardware |
| Glass appearance | macOS 26 or later; compatibility styling on older systems |
| Mouse | AM Infinity .97; other models have not been verified |
| Connection | Bluetooth, direct USB and the 2.4 GHz receiver verified with hardware read/write/restore tests |

## Using the app

| Action | Where to find it |
| --- | --- |
| Remap a button | Click its dot or connected label on the mouse, choose an action, then **保存到鼠标** (Save to mouse) |
| Configure the wheel | Click the wheel, then choose click, scroll up or scroll down |
| Adjust DPI | Click DPI at the bottom, choose a stage, adjust X/Y and save |
| Configure lighting | **光效** (Lighting), select mouse or receiver, adjust the effect, then **保存光效** (Save lighting) |
| Check the battery | Click **电量** (Battery) at the bottom |
| Undo a saved change | **撤销** / **撤销映射** restores the last successful change in the current app session |
| Check official updates | **更新** (Updates) in the top-right corner |
| Device details and backups | **设备信息** (Device information) in the top-right corner |
| Refresh the connection | Press `⌘R`, or choose **刷新设备** from the View menu |

Selecting an action does not write to the device. Saving first creates a backup, then writes the change and reads it back for verification. **Saved onboard DPI and button mappings continue to work after the app quits.** Mac shortcuts use default system key combinations; customized system shortcuts may behave differently.

The black/white selector changes the illustration only. It does not detect the hardware color or change lighting. Collapse the sidebar whenever you like; clicking a mouse hotspot, DPI or battery opens the matching settings again.

## Lighting and connection limits

Mouse effects: Solid, Breathing and Neon, speed 1–10, up to 7 colors. The receiver itself supports Solid, Breathing, Arc, Mosaic, Aurora, Night City and Flow, with speed, brightness and effect-specific colors. Saving creates a raw backup and verifies the entire persisted animation; Undo restores the original bytes.

**Bluetooth and USB support the full multicolor settings.** The 2.4 GHz mouse route has a long-reply limitation, so the app uses compact animations. Some slow multicolor breathing combinations require fewer colors, a higher speed, or Bluetooth/USB. If an existing animation is too long to read safely, the app asks you to switch connections and leaves it intact. The receiver's own seven effects are independent of this limitation and can be configured whenever it is plugged in.

## Backups, updates and troubleshooting

**Backups:** `~/Library/Application Support/AM Native/Backups/`, also accessible from Device information. Files persist across launches; the normal undo history is limited to the current session. If the app reports a pending recovery, keep the message and backup, and use the recovery control shown in the app.

**Receiver connected but mouse unavailable:** wake the physical mouse, quit official settings software and webpages, then press `⌘R`. Run only one copy of AM Native.

**Switching connections:** USB takes precedence over Bluetooth, then the 2.4 GHz receiver. The app refreshes automatically after switching; `⌘R` also refreshes. Bluetooth uses an already paired and connected AM Infinity .97; it does not scan or pair other devices. If access was denied, allow AM Native in System Settings → Privacy & Security → Bluetooth. Switching connections clears in-memory undo receipts; reread the settings before editing.

**Official updates:** while running, the app checks once a day for mouse firmware, receiver firmware and the official Mac driver. Manual checks are available. It only reports versions and links to official pages; it does not download, install or flash them. This is not an auto-updater for AM Native itself.

**Background operation:** saved onboard settings do not require the app to stay open. Scheduled version checks run only while the app is running.

**Not implemented:** gestures, smooth scrolling, per-app profiles and firmware flashing.

## Build from source

Requires an Apple Silicon Mac, full Xcode and a **macOS 26 or newer SDK**. Downloading the prebuilt app does not require Xcode.

```sh
git clone https://github.com/op7418/AM-Native.git
cd AM-Native
bash scripts/fetch-artwork.sh
bash build.sh
open 'build/AM Native.app'
```

The artwork script downloads the mouse illustrations directly from Angry Miao and verifies their hashes; see [third-party notices](THIRD_PARTY_NOTICES.md). A simple fallback icon is generated when the custom release icon is absent.

The build runs protocol, mapping and native-control tests, then produces an ad-hoc-signed app and a command-line probe. Building does not write to your mouse. Set `AM_SWIFTC` and `AM_SDK` to override toolchain paths.

```sh
# Read-only device inspection
build/am-probe read

# Package the current build; an existing archive is never overwritten
bash package.sh
```

See [protocol notes (Chinese)](docs/protocol.md) for implementation details and verification limits. Issues with reproduction steps and pull requests are welcome. Changes that write to hardware should document the target hardware and restore/readback verification. Do not publish personal backups or sensitive log data in issues.

## Author and license

- Author: **歸藏 (Guizang)**
- Twitter: [@op7418](https://twitter.com/op7418)
- Project source: [MIT License](LICENSE)

An independent, unofficial project, not affiliated with Angry Miao. Third-party product images, brand names and trademarks are outside the project's MIT grant; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
