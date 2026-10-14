# Lighting support — 0.6.0 preview

Current result: USB and Bluetooth full lighting, receiver compact mouse lighting and all receiver-local effects passed persisted readback and exact restoration. App save/undo passed on each transport. Receiver long replies remain limited; see final acceptance below. Earlier paragraphs are chronological checkpoints, superseded by later results.

Agent: codex
Change-Id: am-native-20261014-lighting

The owner requested the official lighting features over Bluetooth, direct USB and the receiver. The public official mouse client was inspected without executing or bundling its code. Mouse effects are Solid, Breathing and Neon; speed 1–10 and up to 7 RGB colors. Receiver effects are Solid, Breathing, Arc, Mosaic, Aurora, Night City and Flow, with speed 1–20, brightness 1–255 and per-effect hue/saturation fields.

Independent Swift implementation adds a lighting panel, separate mouse/receiver selection, raw NV backup, complete persisted readback, undo and pending recovery. Receiver configuration uses its own USB interface even when the mouse uses another transport. No pairing, firmware upgrade or factory reset commands are enabled.

Interoperability facts: mouse settings are NV 0x600a, pattern NV 0x6200, read command 0x0a0c (id LE16 + requested length LE16). Response is status + id LE16 + length LE16 + data. Settings are enabled/mode/speed; pattern data is LED count + RGB byte length LE16 + frame interval + RGB frames. Write settings command 0x30b3; save pattern 0x0a0d (NV id + pattern); solid realtime 0x30c0. Receiver read 0x300e and write 0x300d use route 0 and a 13-byte configuration without a response status prefix. The setting/pattern write ACK is not assumed: complete readback is required. Only these NV IDs can be accessed.

Hardware state as of this checkpoint: receiver route read both original lighting configurations successfully; both were disabled. Mouse solid temporary write and exact restore passed (durable verified journals). The subsequent breathing-pattern transaction could not complete; mouse profile queries also timed out, while the receiver itself still answered. User moved the mouse, but communication did not recover. User was asked to power the mouse off and back to 2.4G while leaving the receiver plugged in. Pending original raw backup remains in Application Support/AM Native/Backups/lighting-pending.json. No subsequent lighting write has been attempted after the failed restore. Recovery must precede further tests or release.

Long response polling was revised to drain nonempty fragments at 1 ms and wait 20 ms only on empty reads, matching the official flow; this has not yet been proven to resolve the hardware issue. Bluetooth/USB lighting and receiver effect writes are not yet validated. Offline tests cover raw backup roundtrips, incomplete NV rejection, large fragmented responses, effect/color/speed boundaries and partial-write/identity/profile recovery guards. UI build and existing tests pass. Version 0.6.0 is local development only; installed and released 0.5.0 remain unchanged.


Follow-up: the owner connected the same mouse over USB. Its complete settings and 628-byte test animation matched the pending transaction exactly. A separate, explicit USB recovery tool (not an automatic cross-device restore) backed up the USB state, restored all 40 original pattern bytes and disabled settings, and verified DPI plus all seven mappings unchanged. The original journal was retained as recovered-via-usb; no pending transaction remains. USB hardware tests then passed all three effects with exact restoration; the receiver's own seven effects passed via its independent USB interface. Both mouse and receiver UI save/undo passed, restoring disabled lighting.

Reads now use the official 1000-byte NV request length. Generated animation data stays within that complete-read window by adapting frame duration for longer multi-color cycles. Long-frame draining was also corrected; the precise source of the earlier wireless failure is not yet isolated. Receiver mouse-route retest and Bluetooth lighting remain pending. A dense 255-tick native brightness slider was changed to a continuous slider with rounded numeric values.


Second receiver retest: solid still passed, but reading the 628-byte breathing animation returned no payload, followed by ordinary profile timeouts. The 1000-byte request / faster draining adjustment did not resolve it. The owner reconnected USB; exact test-state match, full original restoration and unchanged DPI/mappings passed again. The original pending journal was archived, not removed. A four-byte NV read was then verified over USB; it returns the requested prefix. Reads now fetch the four-byte animation header, validate its length, then request precisely that many bytes and compare headers. This is not yet proof of a receiver fix.

Initial Bluetooth test: solid write/readback/restore passed. Sending the long breathing pattern timed out before the next settings command. A fresh Bluetooth connection found the original raw state unchanged; guarded recovery succeeded and archived the pending journal. Short characteristic writes (at most 59 bytes and bounded by both CoreBluetooth write limits) are now under test, avoiding ATT long-write assumptions. No new public release or installed-app replacement has occurred.


Bluetooth short-write fix passed all three effects (two colors, speed 7), then the boundary case of seven colors at speed 1. Every full pattern readback and exact original restore passed; DPI and all seven mappings remained unchanged. The earlier failed Bluetooth long write had not changed persistent state. RACE characteristic writes now use at most 59 bytes, bounded by both reported write capacities, and write-only operations complete only on the final write acknowledgement. This prevents an early notification from completing a partially sent request. Receiver long-pattern behavior remains separately unresolved.


Bluetooth App acceptance passed after restarting the local build: connection, breathing save/full readback and undo restored disabled original white animation. The first launch had a CoreBluetooth initialization timeout with TCC activity in system logs; restart resolved it, so no permanent root-cause fix is claimed.

Receiver exact-length retest still failed for the 628-byte pattern. While the owner kept the mouse active, prefix reads of 48 and 128 bytes passed with correctly reassembled fragments; a 256-byte read returned no response and subsequent profile queries timed out. This isolates a reproducible receiver long-reply issue without establishing its exact firmware buffer limit. Source now caps receiver mouse-light reads/writes to 128 bytes, reads the header first and rejects existing larger animations before requesting them. Compact generated patterns preserve cycle time using fewer frames; unsupported slow multi-color breathing combinations fail before creating a pending write. USB/Bluetooth retain the larger budget. Offline tests and build pass; compact receiver hardware verification remains pending. The latest 628-byte receiver test has a durable pending backup awaiting user-assisted Bluetooth/USB recovery. No release/install update yet.


Recovery checkpoint: the owner switched the same mouse to Bluetooth. Its full state exactly matched the pending receiver test, and the explicit cross-transport recovery restored all 40 original animation bytes and settings [0,0,1]. DPI and all mappings were unchanged; pending was archived. No pending lighting transaction remains. The owner has been asked to switch back to the receiver for compact-pattern verification.


## Final acceptance

After the owner switched back to 2.4 GHz, all three compact mouse effects passed full persisted readback and exact original restoration. All seven receiver-local effects passed again. The test ended with ALL_LIGHTS_RESTORED_DPI_MAPPING_UNCHANGED_PASS. In the App, enabling a compact breathing animation, saving, and undoing each reported complete readback agreement. Disabled lighting, original 40-byte white pattern and receiver configuration were restored; no pending transaction remains.

Release scope: USB/Bluetooth support the full UI palette/speed range; receiver mouse animations use at most 128 bytes. Slow multi-color breathing combinations that cannot fit are rejected before writing; an existing longer animation requires Bluetooth/USB to read or change. The exact receiver firmware limit is unknown. Readback verifies configuration, not a visual comparison of physical LEDs. No firmware changes were made. All five offline test suites, release build and ad-hoc signature verification passed. Distribution remains an Apple Silicon preview without Developer ID signing or notarization.
