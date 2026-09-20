# Carplay Gauges

A SwiftUI iOS gauge cluster for Bluetooth LE ELM327-style OBD2 adapters — built to be
developed entirely from Windows/Linux (no Mac, no local Xcode) using
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and a GitHub Actions macOS runner.

## What it does

- Connects to a BLE ELM327 clone (e.g. a generic "DA100"-style adapter) over CoreBluetooth.
  Instead of hardcoding one adapter's GATT UUIDs, it discovers every service/characteristic
  the peripheral exposes and probes for the notify+write pair that actually talks back —
  so unbranded/generic adapters work, not just name-brand ones.
- Polls standard SAE J1979 Mode 01 PIDs (RPM, speed, coolant/oil temp, throttle, load,
  MAP/boost, voltage, etc.) and renders them as analog-style dial gauges with color
  zones and peak-hold, arranged into swipeable, user-customizable pages.
- Has a Demo Mode with simulated data so the UI can be exercised without hardware.
- Handles reconnects (exponential backoff, reconnect-by-cached-peripheral-ID) and keeps
  polling in the background via the `bluetooth-central` background mode.
- Shows up to 4 chosen gauges in a Live Activity (Lock Screen + Dynamic Island). Since
  iOS 18, a running Live Activity is also surfaced on the **CarPlay dashboard**
  automatically — no CarPlay entitlement or CarPlay-specific code needed (a full CarPlay
  app isn't allowed for engine data anyway).
- Ships with no Apple Developer Program entitlements beyond what a free/personal-team
  Apple ID can sign: no push entitlement (Live Activity updates are all local, from the
  app process), no App Groups, nothing that requires a paid account.

## Project layout

- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. Run
  `xcodegen generate` to produce `CarplayGauges.xcodeproj` (not checked in — it's
  regenerated every time, in CI and locally, so there's never a `.xcodeproj` to
  hand-edit or merge-conflict on).
- `Gauges/` — the main app target.
  - `Bluetooth/` — CoreBluetooth transport (`BLECentralController`), the ELM327
    AT-command/PID session (`ELM327Session`), and the demo data generator.
  - `Models/` — the OBD PID catalog/decoder, gauge layout persistence, and the single
    `VehicleDataStore` observable that views bind to.
  - `Views/` — the dial gauge, paged gauge screens, settings, and the gauge/page editor.
  - `LiveActivity/` — starts/updates the Live Activity from the app process.
  - `Shared/` — `ActivityAttributes` shared with the widget extension target.
- `GaugesWidget/` — the widget extension target that renders the Live Activity
  (Lock Screen banner + Dynamic Island). This is a separate Xcode target because
  ActivityKit requires the presentation to live in a widget extension, even though only
  the main app ever calls `Activity.request`/`.update`.
- `.github/workflows/build.yml` — macOS runner CI: installs XcodeGen, generates the
  project, builds an **unsigned** Release `.app` (`CODE_SIGNING_ALLOWED=NO`), zips it into
  `CarplayGauges.ipa`, and uploads it as a workflow artifact.

## Getting the .ipa

Push to this repo (or run the workflow manually from the Actions tab) and download the
`CarplayGauges-ipa` artifact from the finished run.

## Installing with AltStore (no Mac required)

1. Install [AltServer](https://altstore.io) on your Windows machine and sign in with a
   free Apple ID.
2. Install AltStore on your iPhone via AltServer (over USB or Wi-Fi).
3. Download `CarplayGauges.ipa` from the Actions artifact and either AirDrop/copy it to
   your phone and open it with AltStore, or drop it onto AltServer's tray icon and choose
   "Install" targeting your device. AltServer re-signs the unsigned `.ipa` with your
   Apple ID's certificate during installation — that's why CI doesn't sign it.
4. Free Apple ID apps expire after 7 days and re-sign automatically whenever AltServer
   and your phone are on the same Wi-Fi (or via AltStore's background refresh).

## Notes / limitations

- The Live Activity updates locally while the app has execution time (foreground, or
  background via the Bluetooth background mode) — there's no push entitlement, so
  updates can pause if iOS fully suspends the app for a while.
- Only standard OBD-II PIDs are used, since manufacturer-specific enhanced PIDs vary by
  ECU/trim and can't be verified generically. A "Boost / Vacuum" gauge is included,
  computed from MAP − barometric pressure.
- Gauges, pages, and the 4 Live Activity slots are fully configurable from in-app
  Settings → Customize Gauges.
