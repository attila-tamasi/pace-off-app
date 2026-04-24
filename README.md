# Pace Off

A no-excuses running app for iPhone and Apple Watch. Reads your VO₂ max and runs from Apple Health, computes a daily push target, and refuses to let you skip.

iOS 26 / watchOS 26 minimum. Swift 6, SwiftUI. No accounts. No servers. Privacy label: *Data Not Collected*.

---

## What's in this folder

```
Pace Off/
├── project.yml                      ← XcodeGen spec (defines all targets)
├── PaceOff/                         ← iPhone app
│   ├── PaceOffApp.swift
│   ├── Info.plist  ·  PaceOff.entitlements
│   ├── Services/   (HealthKitService, NotificationScheduler)
│   ├── ViewModels/ (TodayViewModel)
│   ├── Views/      (Today, History, Trends, Settings, Onboarding, RunDetail, Root)
│   └── Assets.xcassets/
├── PaceOffWatch Watch App/          ← Apple Watch app
│   ├── PaceOffWatchApp.swift
│   ├── Info.plist  ·  PaceOffWatch.entitlements
│   ├── Services/   (WorkoutSessionManager — HKWorkoutSession + LiveBuilder)
│   └── Views/      (WatchTodayView, RunningWorkoutView, PostRunView)
├── PaceOffWidget/                   ← Lock Screen + Home Screen widget
│   ├── PaceOffWidget.swift  ·  PaceOffWidgetBundle.swift
│   ├── Info.plist  ·  PaceOffWidget.entitlements
│   └── Assets.xcassets/
├── PaceOffShared/                   ← shared by all targets
│   ├── PushTargetEngine.swift       ← the core algorithm (PRD §7)
│   ├── VoiceCopy.swift              ← drill sergeant voice library (PRD §8)
│   ├── RunTarget.swift  ·  Tone.swift  ·  RunRecord.swift  ·  VO2MaxSnapshot.swift
│   └── AppGroup.swift               ← shared App Group + UserDefaults keys
├── PaceOffTests/
│   └── PushTargetEngineTests.swift  ← full coverage of PRD §7.3 worked example
└── Pace Off - PRD.docx              ← full product spec
```

---

## Build & run — recommended path (XcodeGen)

XcodeGen generates the `.xcodeproj` from `project.yml`. It handles all the multi-target wiring (iOS app + watchOS app + widget extension + tests) correctly the first time.

```bash
cd "/path/to/Pace Off"
brew install xcodegen
xcodegen
open PaceOff.xcodeproj
```

In Xcode:

1. Select the **PaceOff** target → **Signing & Capabilities** → set your **Team** (Apple ID).
2. Repeat for **PaceOff Watch App** and **PaceOffWidget** targets.
3. The bundle identifiers (`com.paceoff.app`, `com.paceoff.app.watchkitapp`, `com.paceoff.app.widget`) and the App Group (`group.com.paceoff.app`) are already configured. If you don't own that prefix, change them in `project.yml` and re-run `xcodegen`.
4. Plug in your iPhone (or use the simulator) and ⌘R.

The Watch app builds and installs alongside the iPhone app when both are deployed to a paired Watch.

### Re-generate after editing `project.yml`

```bash
xcodegen
```

---

## Build & run — manual Xcode path (no XcodeGen)

If you'd rather not install XcodeGen:

1. **File → New → Project → iOS → App**. Name it `PaceOff`, language Swift, interface SwiftUI, set **Organization Identifier** to `com.paceoff.app`.
2. Drag the `PaceOff/`, `PaceOffShared/`, `PaceOffTests/` folders into the project navigator. Choose **Create groups**.
3. **File → New → Target → watchOS → App** (note: not "Watch App for iOS App" if Xcode 26 has separated this). Name it `PaceOff Watch App`. Drag in the contents of `PaceOffWatch Watch App/` plus the `PaceOffShared/` folder reference.
4. **File → New → Target → iOS → Widget Extension**. Name it `PaceOffWidget`. Replace the generated files with the contents of `PaceOffWidget/`, plus `PaceOffShared/`.
5. For **all three app targets** (iPhone, Watch, Widget), in Signing & Capabilities:
   - Add **App Groups** capability with `group.com.paceoff.app`.
6. For the iPhone and Watch targets only:
   - Add **HealthKit** capability (enable Background Delivery on iPhone).
   - Add **Background Modes** → Background processing (iPhone) and Workout processing (Watch).
7. Use the provided `Info.plist` files as reference (especially the `NSHealthShareUsageDescription` strings — Apple will reject the build without them).

---

## Testing

```bash
xcodebuild test -scheme PaceOff -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The `PushTargetEngineTests` suite covers the worked example from PRD §7.3 plus edge cases (3+ day skip restart, hard ceiling clamp, recovery after a long run, fatigue guard).

---

## Architecture at a glance

- **`PushTargetEngine`** is pure Swift, no HealthKit imports — fully testable. Inputs: 90 days of runs, 90 days of VO₂ max, 14 days of resting HR. Output: distance, tone, reasoning.
- **`HealthKitService`** lives on `@MainActor` and exposes async methods. All reads are `HKSampleQuery` / `HKStatisticsQuery`. Background updates via `HKObserverQuery` + `enableBackgroundDelivery`.
- **`NotificationScheduler`** uses `UNUserNotificationCenter` with calendar triggers. Three pushes max per day per PRD §9.1.
- **iOS app + Watch app + Widget** share state via the `group.com.paceoff.app` App Group's `UserDefaults`. The widget reads the cached `RunTarget` JSON written by the iPhone app on each refresh.
- **Watch workout** uses `HKWorkoutSession` + `HKLiveWorkoutBuilder` with a running configuration. Running dynamics (power, stride, vertical oscillation, ground contact) are surfaced live.

---

## Where to make your first changes

- **Voice copy:** `PaceOffShared/VoiceCopy.swift`
- **Algorithm tuning:** constants at the top of `PaceOffShared/PushTargetEngine.swift`
- **Notification times:** defaults in `PaceOffShared/AppGroup.swift`, overridable in Settings
- **Visual design:** `PaceOff/Views/TodayView.swift` (the hero card)
- **App icon:** drop a 1024×1024 PNG into `PaceOff/Assets.xcassets/AppIcon.appiconset/` and reference it from `Contents.json`

---

## Known gaps (intentional for MVP)

- App Icon is empty — drop a PNG in to ship.
- WatchConnectivity bridge for "Start Run from iPhone" is stubbed in `TodayView.startRun()`. Wire up `WCSession` in v1.1.
- Live Activity for in-progress run is not yet implemented.
- The widget shows status colors (green/amber/red) based on time-of-day only; it doesn't currently know if a run is "in progress" — that requires the WatchConnectivity bridge above.
- No localization yet (English only).

---

## License

Personal project — all rights reserved by Attila Tamasi.
