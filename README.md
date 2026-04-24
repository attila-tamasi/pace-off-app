# Pace Off

A no-excuses running app for iPhone and Apple Watch. Reads your VO₂ max and runs from Apple Health, computes a daily push target, and refuses to let you skip.

iOS 26 / watchOS 26 minimum. Swift 6, SwiftUI. No accounts. No servers. Privacy label: *Data Not Collected*.

---

## What's in this folder

```
Pace Off/
├── project.yml                      ← XcodeGen spec (defines all targets)
├── PaceOff.xcodeproj/               ← Generated Xcode project — open this in Xcode
├── PaceOff/                         ← iPhone app
│   ├── PaceOffApp.swift
│   ├── Info.plist  ·  PaceOff.entitlements
│   ├── Services/   (HealthKitService, NotificationScheduler)
│   ├── ViewModels/ (TodayViewModel)
│   ├── Views/      (Today, History, Trends, Settings, Onboarding, RunDetail,
│   │                Root, VO2MaxDetail)
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
│   ├── VoiceCopy.swift              ← drill-sergeant voice library (PRD §8)
│   ├── RunTarget.swift  ·  Tone.swift  ·  RunRecord.swift  ·  VO2MaxSnapshot.swift
│   └── AppGroup.swift               ← shared App Group + UserDefaults keys
├── PaceOffTests/
│   └── PushTargetEngineTests.swift  ← full coverage of PRD §7.3 worked example
├── Pace Off - PRD.docx              ← full product spec
├── README.md
└── .gitignore
```

---

## Build & run — quick path

The `.xcodeproj` is already generated and committed. Just open it.

```bash
open "PaceOff.xcodeproj"
```

In Xcode:

1. Select the **PaceOff** target → **Signing & Capabilities** → set your **Team** (Apple ID).
2. Repeat for **PaceOff Watch App** and **PaceOffWidget** targets.
3. The bundle identifiers (`com.paceoff.app`, `com.paceoff.app.watchkitapp`, `com.paceoff.app.widget`) and the App Group (`group.com.paceoff.app`) are pre-configured.
4. Pick a destination (iPhone 17 Pro simulator, or a real iPhone with a paired Watch) and ⌘R.

The Watch app and widget extension build and install alongside the iPhone app automatically.

### If you don't own the `com.paceoff.app` bundle prefix

Search-and-replace `com.paceoff.app` across `project.yml`, the three `*.entitlements` files, and `PaceOffShared/AppGroup.swift`, then either re-run XcodeGen or edit the bundle IDs directly in Xcode → Signing & Capabilities for each target.

---

## Build & run — XcodeGen path (regenerate the project)

[XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the `.xcodeproj` from `project.yml`. Use it if you change targets, add capabilities, or just prefer not to commit the `.xcodeproj`.

```bash
brew install xcodegen
xcodegen
open PaceOff.xcodeproj
```

Re-run `xcodegen` any time you edit `project.yml`.

---

## Testing

```bash
xcodebuild test -scheme PaceOff -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The `PushTargetEngineTests` suite covers the worked example from PRD §7.3 plus edge cases (3+ day skip restart, hard ceiling clamp, recovery after a long run, fatigue guard).

---

## Architecture at a glance

- **`PushTargetEngine`** is pure Swift, no HealthKit imports — fully testable. Inputs: 90 days of runs, 90 days of VO₂ max, 14 days of resting HR. Output: distance, tone, reasoning.
- **`HealthKitService`** lives on `@MainActor` and exposes async methods. All reads are `HKSampleQuery` / `HKStatisticsQuery`. Background updates via `HKObserverQuery` + `enableBackgroundDelivery`. Reads the user's age from the `dateOfBirth` characteristic.
- **`NotificationScheduler`** uses `UNUserNotificationCenter` with calendar triggers. Three pushes max per day per PRD §9.1.
- **`TodayView`** shows today's target, an inline "you ran today" card (when applicable), and a supporting stat grid. Tap the VO₂ MAX card for a 12-month chart.
- **iOS app + Watch app + Widget** share state via the `group.com.paceoff.app` App Group's `UserDefaults`. The widget reads the cached `RunTarget` JSON written by the iPhone app on each refresh.
- **Watch workout** uses `HKWorkoutSession` + `HKLiveWorkoutBuilder` with a running configuration. Running dynamics (power, stride, vertical oscillation, ground contact) are surfaced live.

---

## Where data lives

Pace Off has no database. Everything boils down to two stores:

- **Apple Health** (via HealthKit) is the source of truth for runs, VO₂ max, heart rate, running dynamics, and the user's age. Re-fetched on every refresh; never cached to disk.
- **App Group `UserDefaults`** (`group.com.paceoff.app`) holds a tiny set of values: the latest computed `RunTarget` (JSON), the current voice line, notification times, the chosen voice tone, and a couple of flags (onboarding complete, ran today). This is what the Watch app and widget read so they can render instantly without re-running the algorithm.

Delete the app and you lose nothing — your runs and VO₂ max stay in Health.

---

## Where to make your first changes

- **Voice copy:** `PaceOffShared/VoiceCopy.swift`
- **Algorithm tuning:** constants at the top of `PaceOffShared/PushTargetEngine.swift`
- **Notification times:** defaults in `PaceOffShared/AppGroup.swift`, overridable in Settings
- **Visual design:** `PaceOff/Views/TodayView.swift` (the hero card)
- **VO₂ max explainer copy:** `PaceOff/Views/VO2MaxDetailView.swift`
- **App icon:** drop a 1024×1024 PNG into `PaceOff/Assets.xcassets/AppIcon.appiconset/` and reference it from `Contents.json`

---

## Known gaps (intentional for MVP)

- App Icon is empty — drop a PNG in to ship.
- WatchConnectivity bridge for "Start Run from iPhone" is not wired. The Start Run button was intentionally removed from `TodayView` in this milestone — start the run on the Watch.
- Live Activity for in-progress run is not yet implemented.
- The widget shows status colors (green/amber/red) based on time-of-day only; it doesn't currently know if a run is "in progress" — that requires the WatchConnectivity bridge above.
- No localization yet (English only).

---

## License

Personal project — all rights reserved by Attila Tamasi.
