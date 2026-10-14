# 0.5.0 Bluetooth and direct USB support

Agent: codex
Change-Id: am-native-20261014-transports

The owner requested Bluetooth and direct USB support, and connected the mouse over Bluetooth first. The app now uses CoreBluetooth's RACE GATT channel for the already connected AM Infinity .97, alongside the existing USB HID channel. Selection prefers direct USB, then Bluetooth, then the receiver; ambiguity within one transport is rejected. Direct USB accepts both vendor/product pairs listed by the official client. Connection changes refresh the UI and discard stale in-memory undo receipts; durable backups and identity/profile checks are preserved.

Bluetooth was verified on hardware through the application's transaction services: battery 65%, active DPI 3400, inactive stage 400→450→400 with exact full-payload restoration, back button temporarily mapped to Cmd+C and restored with all seven mappings identical to the original, mouse firmware 1.8.4. The app never writes pairing, firmware, flash or reset commands. System permission is required and documented.

Offline tests cover BLE notification fragmentation, completion/timeout races, USB/Bluetooth/receiver precedence, unknown interfaces and ambiguous devices, plus existing protocol, mapping and native-control regression tests. Build succeeds. The original approved icon is retained in the local build.

USB hardware validation passed with receiver and mouse both attached: the app selected the mouse's direct USB interface (0x0e8d:0x0880), read battery/DPI/version, and restored both the DPI transaction and all seven mappings exactly. The alternate vendor/product pair remains source-supported but has not been tested on hardware.

The owner granted macOS Bluetooth permission. The app automatically switched from USB to Bluetooth after the cable was removed. Both USB and Bluetooth UI save/undo tests passed, restoring the existing back-button Mission Control mapping after a temporary Copy mapping. Active DPI remained 3400. Local backup journals and device traces are not published.

Version 0.5.0 remains an arm64 preview with ad-hoc signing and no notarization. The release adds bilingual connection/permission instructions. No firmware, pairing or factory-reset operations were performed.
