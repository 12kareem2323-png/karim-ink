# Optional direct Quick Keys bridge

`QuickKeysBridge.swift` adapts packet layouts from the public MIT project by Julian Waller:

- Repository: https://github.com/Julusian/node-xencelabs-quick-keys
- Reviewed commit: `8cfbb9141c3b0df005a7f20f2bf090029d6a7948`
- License: MIT, Copyright (c) 2021 Julian Waller. Complete notice is in `LICENSE.txt`.
- Original source checkout: `work/quickkeys-reference`, obtained from the public repository, not the installed Xencelabs application.
- Reviewed files: `packages/core/src/ids.ts`, `device.ts`, `wireless-device.ts`, `types.ts`, `manager.ts`; `packages/node/src/device.ts`, `manager.ts`; `packages/webhid/src/device.ts`, `manager.ts`; upstream packet test vectors.

The community library explicitly distinguishes itself from the manufacturer's software. This is an optional community bridge, not a vendor SDK, vendor endorsement or driver replacement.

The native implementation permits only vendor `0x28bd` and products `0x5202` (wired Quick Keys) / `0x5203` (wireless receiver), with vendor usage page `0xff0a` and usage `0x01`. The upstream Node implementation also selects USB interface 2; the native bridge checks that interface when the device publishes `bInterfaceNumber`. Keyboard and mouse usages are excluded by matching.

The bridge starts only on an explicit action while SketchGlide is frontmost. IOHIDManager opens with zero options, without seizing devices. It uses output report ID `0x02`, not feature reports; 32-byte reports include the ID in byte zero, as specified by Apple's installed public IOHIDDevice header. A wired device subscribes to the public community event stream; wireless discovery selects the first responding Quick Keys and routes packets by its six-byte address.

OLED labels change with Drawing / Math / Circuits workspace. Four dial functions are Zoom, Width, Pens and History. Input mapping assumes the standard community key bitmap with eight label keys followed by Set and Dial buttons; their physical placement and orientation require testing. No screen orientation, brightness, sleep-time, firmware, driver profile or macOS permission changes are made.

Output reports are submitted asynchronously with a bounded queue and retained packet storage. Stop unregisters input callbacks and clears pending reports immediately. If an accepted output is in flight, its ticket retains the packet, device and retired manager until completion; the callback then closes the retired manager and releases that storage. A wireless-child disconnect clears unsent reports for that child. No guessed restore packet is sent. The reviewed source contains no previous-label readback, complete OLED restoration, driver ownership coordination or documented device-mode restoration command. Earlier OLED labels may remain until the official driver updates them. Shared access can fail or conflict with the vendor driver's output; duplicate actions from existing driver mappings are also possible. The bridge automatically stops when the app loses focus, while preserving the supported driver shortcut route.

Validation was offline: packet bytes were checked against upstream vectors, malformed/truncated data was rejected, and the native file was compiled with the macOS 26.5 SDK targeting macOS 14. No IOHID manager was opened, device connected, or report written during QA. Physical input, labels, wireless routing and driver coexistence remain unverified.
