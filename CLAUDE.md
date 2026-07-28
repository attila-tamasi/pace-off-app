# Pace Off — Project Instructions

## What this app is
iOS + watchOS running app. Reads runs, VO₂ max, HR from Apple Health, computes a daily push target, prescribes multi-week Daniels-VDOT training plans, and projects race times. One-liner: **"The running buddy that knows when to push you and when you need rest."**

No accounts (Sign in with Apple is optional). No servers. Privacy label: *Data Not Collected*.

## Tech stack
- SwiftUI, Swift 6, iOS 26 / watchOS 26 minimum
- HealthKit for runs, VO₂ max, HR, running dynamics, dateOfBirth
- Modern Swift Observation framework (`@Observable`, `@Environment(Type.self)`) — **not** `ObservableObject`
- Swift Concurrency (async/await); no Combine unless unavoidable
- Persistence: App Group `UserDefaults` + small JSON files in the App Group container. **No SwiftData, no CoreData, no CloudKit, no third-party backend.**
- XcodeGen (`project.yml`) generates `PaceOff.xcodeproj` — regenerate after changing targets: `xcodegen generate`
- No third-party Swift packages in V1 unless explicitly agreed

## Targets in this workspace
- `PaceOff` — iPhone app
- `PaceOff Watch App` — watchOS companion (uses `HKWorkoutSession` + `HKLiveWorkoutBuilder`)
- `PaceOffWidget` — Lock Screen / Home Screen widget
- `PaceOffShared` — shared value types + pure engines (no UIKit, no HealthKit imports where avoidable — keep testable)
- `PaceOffTests` — XCTest suite; unit tests are cheap and expected

All targets read/write shared state through the `group.com.paceoff.app` App Group.

## Design rules
- iOS 26 **Liquid Glass** design language: prefer native materials (`.glassEffect`, `.background`, system backgrounds); never fake glass with manual blur/opacity hacks
- Follow Apple HIG: SF Symbols only, Dynamic Type, system colors, standard navigation
- Support Dark Mode from day one; respect safe areas
- Minimal UI: one screen = one job. Don't stuff dashboards with stats.
- Accessibility: VoiceOver labels on interactive elements, sensible Dynamic Type behavior

## Architecture
- Feature-based folder layout under `PaceOff/Views/` (one folder per screen or feature — e.g. `Views/Training/`, `Views/Legal/`, `Views/Preview/`)
- Views stay dumb; observable services own state and side effects (`ProfileStore`, `TrainingPlanStore`, `HealthKitService`, `NotificationScheduler`, etc.)
- Pure algorithms (`PushTargetEngine`, `TrainingPlanGenerator`, `GoalPredictionService`, `VDOTCalculator`) live in `PaceOffShared` — `Sendable`, no I/O, unit-tested
- HealthKit access is confined to `HealthKitService` (`@MainActor`). Nothing else imports `HealthKit`.
- Preview support in `Views/Preview/PreviewSupport.swift`: sample data + `PreviewProfileStore`, gated behind `#if DEBUG`

## Working style
- Work feature-by-feature per `SPEC.md`; keep PRs small and compilable
- Propose a plan for anything non-trivial before touching code
- **Never** introduce CloudKit, SwiftData, or a third-party dependency without confirming — flag it, wait for a yes
- Match existing patterns before inventing new ones (e.g. new stores follow the `@Observable` + App Group `UserDefaults` / JSON-in-container pattern used by `ProfileStore`, `TrainingPlanStore`, `HealthDataCache`)
- Modern `#Preview` blocks use `.environment(...)` injection — not `.environmentObject` and not custom preview `ObservableObject` wrappers
- No comments narrating the current task or PR ("added for issue #123") — those belong in the PR description

## Build & test
```
xcodebuild build -scheme PaceOff -destination 'generic/platform=iOS Simulator'
```

Do not run `xcodebuild test` in ad-hoc automation — it hangs on host device discovery in some environments. Run tests from Xcode.

## Scope discipline
The training-plan feature is **in scope** and shipping — a VDOT-based generator (`TrainingPlanGenerator`), a picker, a detail view, and a persistent active plan (`TrainingPlanStore`). Do not remove or gut it.

Anything that would require **CloudKit, a server, a paywall, Android, or a chat surface** is out of scope for the current milestone. `SPEC.md` lists proposals that fall in these categories under a **V2+ / needs decision** section — they are ideas, not commitments. Ask before starting one.

## Current priorities (2026-07)
- **iPhone-first**: onboarding, home, run detail, training plan, profile.
- **watchOS app is deprioritized** for the current wave. The `PaceOff Watch App` target still builds and ships, but don't spend cycles polishing it, adding features, or reworking the workout session code unless the user explicitly asks. Bugfixes to keep it building are fine.
- Widget stays in scope but only as a "renders the cached target" surface — the WatchConnectivity-dependent in-progress-run state is on hold with the Watch work.
