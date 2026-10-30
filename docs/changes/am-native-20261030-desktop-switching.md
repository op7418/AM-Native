# Desktop switching actions — 0.6.1

Agent: codex
Change-Id: am-native-20261030-desktop-switching

用户直接要求：在鼠标按键绑定中加入切换桌面选项。Adds Previous Desktop (Control–Left) and Next Desktop (Control–Right) to the existing shared action list, including both side buttons. The selected action explains the macOS shortcut prerequisite. It switches adjacent Spaces, including full-screen apps, rather than toggling a fixed pair of numbered desktops.

Reuses the existing onboard keyboard mapping protocol and backup/readback/undo flow. HID arrow usages are 0x50 and 0x4F from Apple's SDK; Control is modifier 1 in the verified device protocol. No existing mapping is changed automatically and no OS shortcut settings are changed.

Validation: release build and existing offline suites; installed UI inspection of both side-button lists. Physical shortcut execution requires the user to save a binding and press the actual mouse button; not claimed as hardware-verified in this change.
