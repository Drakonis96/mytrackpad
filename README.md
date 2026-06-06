# MyTrackpad

Turn your iPhone/iPad into a **wireless trackpad and keyboard** for your Mac.
A native, beautiful and minimal app with **Liquid Glass** (iOS 26), **portrait and landscape**
support, real multi-touch gestures, a keyboard, arrow keys and quick-function buttons.

The project ships **two apps** (a trackpad needs a receiver on the Mac):

| App | Folder | What it does |
|-----|--------|--------------|
| **MyTrackpad** (iOS) | `iOS/` | The touch surface, keyboard and buttons. Discovers the Mac and sends it the gestures. |
| **MyTrackpad Server** (macOS) | `macOS/` | A menu-bar agent. Receives the gestures and turns them into real mouse/keyboard events. |

The shared code (protocol and transport) lives in `Shared/`.

---

## How the connection works

- The Mac advertises itself over **Bonjour** (`_mytrackpad._tcp`) on the local network and listens on a **fixed TCP port (52525)**.
- The iPhone **discovers it automatically** — no need to type IPs or ports.
- A **manual-IP fallback** is built in for networks where multicast/mDNS is blocked (client isolation, VPNs, or sandboxed loaders like LiveContainer). The Mac shows its IP with a **Copy** button; paste it into the iPhone app.
- `includePeerToPeer` is enabled, so it also works over Apple's **direct link (AWDL / Bluetooth-assisted)** even without a shared router. For a trackpad this is the lowest-latency option; pure BLE (GATT) is too slow.
- The transport is **TCP with `TCP_NODELAY`** and length-prefixed JSON messages.

---

## Install (no Xcode required)

Download the latest artifacts from the [**Releases**](https://github.com/Drakonis96/mytrackpad/releases) page.

### 1. Mac — `MyTrackpad-Server.dmg`

1. Open the DMG and drag **MyTrackpad Server** into **Applications**.
2. The app is **ad-hoc signed**. The first time, Gatekeeper may block it: **right-click → Open**, then confirm. (Or run `xattr -dr com.apple.quarantine "/Applications/MyTrackpad Server.app"`.)
3. Launch it — an icon appears in the menu bar.

### 2. iPhone/iPad — `MyTrackpad.ipa`

The IPA is **unsigned** (no developer certificate is baked in). Install it with any sideloading method:

**Option A — AltStore / SideStore source (recommended, gets updates):**

1. In AltStore/SideStore go to **Browse → Sources → + (Add Source)**.
2. Paste the source URL:
   ```
   https://raw.githubusercontent.com/Drakonis96/mytrackpad/main/source.json
   ```
3. Open the **MyTrackpad Source**, tap **MyTrackpad → Free / Install**. AltStore signs it with your Apple ID on-device.

**Option B — Direct sideload:** install `MyTrackpad.ipa` with [AltStore](https://altstore.io), [SideStore](https://sidestore.io) or [Sideloadly](https://sideloadly.io); they re-sign it with your Apple ID.

> **LiveContainer note:** discovery via Bonjour usually fails inside LiveContainer because the host's `Info.plist` does not declare `_mytrackpad._tcp`. Use the **manual-IP connection** instead (see *Usage* below), and make sure **LiveContainer** has the **Local Network** permission enabled in *Settings → Privacy & Security → Local Network*. For full Bonjour support, install the app natively (SideStore/AltStore/Xcode).

---

## Usage

1. **On the Mac:** open **MyTrackpad Server**. The first run, macOS asks for **Local Network** permission (accept it) and for **Accessibility**.
   The menu has a **“Grant Accessibility…”** button that opens Settings — enable *MyTrackpad Server* there.
   > When you grant Accessibility, **the app restarts itself** to activate event injection.
   > Without Accessibility the connection works, but the cursor won't move and nothing will be typed.
2. **On the iPhone:** open **MyTrackpad**.
   - **Automatic:** your Mac appears in the list — tap it to connect.
   - **Manual (fallback):** if your Mac doesn't appear, read the IP shown in *MyTrackpad Server* on the Mac, tap **Copy**, then on the iPhone type or paste it under **“Don't see your Mac?”** and tap **Connect by IP**.
3. Done — use the surface like a trackpad.

---

## Gestures

| Gesture | Action |
|---------|--------|
| One finger sliding | Move the cursor |
| Single tap | Left click |
| Two-finger tap | Right click (context menu) |
| Two fingers sliding | Scroll |
| Pinch | Zoom (⌘+scroll) |
| Double-tap + hold and move | Drag and drop |
| Bottom buttons | Explicit left / right click |

## Keyboard and functions

- **Keyboard:** a button opens the system keyboard; what you type (including backspace and return) is sent to the Mac.
- **Arrow keys** and **Esc / Tab / Return / Delete**.
- **Quick functions:** Brightness ±, Volume ±, Mute, Play/Pause, Previous/Next, Mission Control, Spotlight, Zoom (Accessibility zoom) and Dictation.

> Brightness, Zoom and Dictation depend on hardware and macOS settings
> (e.g. “Use keyboard shortcuts to zoom” under *Accessibility*). Everything else works out of the box.

## Settings

Cursor speed, natural scrolling and haptics are configurable from the ⚙️ icon.

---

## Build from source

### Requirements

- macOS 26 (Tahoe) and iOS 26 — required for the Liquid Glass APIs.
- Xcode 26+.
- [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`) to generate the project.

### Generate and open the project

```bash
cd mytrackpad
xcodegen generate
open MyTrackpad.xcodeproj
```

> The `.xcodeproj` is generated from `project.yml` and is in `.gitignore`. Re-run
> `xcodegen generate` whenever you change `project.yml` or add/remove files.

### Build from the terminal

```bash
# macOS app
xcodebuild -project MyTrackpad.xcodeproj -scheme MyTrackpadMac -configuration Debug build

# iOS app (simulator)
xcodebuild -project MyTrackpad.xcodeproj -scheme MyTrackpad \
  -destination 'generic/platform=iOS Simulator' build
```

To install on a **real iPhone**: open the project in Xcode, select the `MyTrackpad` target,
under *Signing & Capabilities* pick your *Team* and run. (The `DEVELOPMENT_TEAM` field is left empty on purpose.)

### Regenerate the distributable artifacts (DMG + IPA)

```bash
./tools/build-dist.sh
```

This produces `MyTrackpad-Server.dmg` (ad-hoc signed) and an unsigned `MyTrackpad.ipa` on your Desktop.

---

## Project structure

```
mytrackpad/
├── project.yml               # Project definition (XcodeGen)
├── source.json               # AltStore/SideStore source
├── Shared/
│   ├── ControlMessage.swift  # iPhone → Mac message model
│   └── Framing.swift         # Length-prefix framing + Bonjour service type + port
├── iOS/
│   ├── MyTrackpadApp.swift   # Entry point + background
│   ├── AppModel.swift        # App state
│   ├── Networking.swift      # Bonjour discovery + TCP client
│   ├── DiscoveryView.swift   # Device-search / manual-IP screen
│   ├── ControllerView.swift  # Main trackpad screen
│   ├── TrackpadView.swift    # Multi-touch surface (UIKit)
│   ├── KeyboardCaptureField.swift
│   └── Components.swift       # Arrows, functions, settings
├── macOS/
│   ├── MyTrackpadMacApp.swift # Menu bar + state
│   ├── TrackpadServer.swift   # Bonjour listener + receive loop
│   ├── EventInjector.swift    # Event injection (CGEvent / NSEvent)
│   └── LocalAddress.swift     # Local IPv4 detection for manual connection
└── tools/
    ├── build-dist.sh          # Builds the DMG + IPA
    ├── makeicons.swift        # Generates the icon assets from logo.png
    └── testclient.swift       # Stress-test client
```

## Technical notes

- The macOS app is built **without the sandbox** (`ENABLE_APP_SANDBOX = NO`): it injects system events
  and opens a network server, which is awkward inside the sandbox for a personal utility.
- Cursor movement is **relative** (like a physical trackpad) and clamped to the bounds of the active displays.
  The server keeps an internal "virtual" cursor position and accumulates deltas there to avoid stutter during fast moves.
- Media keys are sent as `NSSystemDefined` events (NX_KEYTYPE_*); the rest as keyboard `CGEvent`s.

## License

MIT
