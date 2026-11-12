# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is
iOS + watchOS running app. Reads runs, VO₂ max, HR from Apple Health, computes a daily push target, prescribes multi-week Daniels-VDOT training plans, and projects race times. One-liner: **"The running buddy that knows when to push you and when you need rest."**

No accounts (Sign in with Apple is optional). No servers. Privacy label: *Data Not Collected*.

Companion docs: `ROADMAP.md` (the prioritised backlog: what to build next), `LOOP.md` (how Claude works through the roadmap on its own), `ARCHITECTURE.md` (where the app is going: the no-backend decision, the Apple Intelligence design, the building blocks to come), `docs/research-2026-11.md` (the competitor research behind both, in Hungarian), `SPEC.md` (shipped features + V2 proposals), `README.md` (build/run walkthrough), `Pace Off - PRD.docx` (full product spec — the PRD § references in code comments point here).

## Tech stack
- SwiftUI, Swift 6, iOS 26 / watchOS 26 minimum
- HealthKit for runs, VO₂ max, HR, running dynamics, dateOfBirth
- Modern Swift Observation framework (`@Observable`, `@Environment(Type.self)`) — **not** `ObservableObject`
- Swift Concurrency (async/await); no Combine unless unavoidable. `SWIFT_STRICT_CONCURRENCY` is currently `minimal` (MVP scaffold — to be tightened later).
- FoundationModels (Apple Intelligence, on-device) is used for optional voice-line rewrites — system framework, always behind `#if canImport` with a canned-copy fallback, in the foreground only, and a rewrite is shown only when `NarrationCheck` finds the canned line's numbers in it
- Persistence: App Group `UserDefaults` + small JSON files in the App Group container. **No SwiftData, no CoreData, no CloudKit, no third-party backend.**
- XcodeGen (`project.yml`) generates `PaceOff.xcodeproj` — regenerate after changing targets: `xcodegen generate`
- No third-party Swift packages in V1 unless explicitly agreed

## Targets & layout
Four targets defined in `project.yml`:
- `PaceOff` — iPhone app (sources: `PaceOff/`)
- `PaceOff Watch App` — watchOS companion (sources: `PaceOffWatch Watch App/` — note the folder name differs from the target name)
- `PaceOffWidget` — Lock Screen / Home Screen widget (draws the day the app caches through `WidgetCache` in App Group `UserDefaults`; a day cached on an earlier date shows as "Open Pace Off")
- `PaceOffTests` — XCTest suite (`PushTargetEngineTests`, `TrainingPlanGeneratorTests`, `TrainingPlanReconcilerTests`, `GoalPredictionServiceTests`, `HealthDataCacheTests`, `ReadinessEngineTests`, `DailyPushPlannerTests`, `VoiceCopyTests`, `WidgetCacheTests`, `HeartTrendTests`, `WorkoutProfileTests`, `WeekReviewTests`, `RunWindowPlannerTests`, `NarrationCheckTests`, `DayPrescriptionTests`, `SingleRunCapTests`, `WorkoutBlocksTests`, `WatchSchedulePlannerTests`, `BestEffortsTests`, and others); unit tests are cheap and expected

`PaceOffShared/` is **not a target** — it's a source folder compiled directly into every target above. Keep it free of UIKit, and free of HealthKit where avoidable, so it stays testable.

All targets read/write shared state through the `group.com.paceoff.app` App Group. Keys and the container URL live in `PaceOffShared/AppGroup.swift`. JSON files in the container: `training-plan.json` (active plan), `health-cache.json` (Health snapshot), `profile-photo.jpg`.

The app icon is one opaque 1024×1024 PNG, the same file in the iOS, widget and watch `AppIcon.appiconset`s. iOS derives the dark and tinted appearances. Don't build an icon from SF Symbols: their licence rules them out of app icons.

## Design rules
- iOS 26 **Liquid Glass** design language: prefer native materials (`.glassEffect`, `.background`, system backgrounds); never fake glass with manual blur/opacity hacks
- Screens read like Apple's Health app: large titles, data in `MetricCard`s (solid `secondarySystemGroupedBackground` cards with a coloured symbol + category, a big value, an optional mini chart). Glass stays on the navigation layer (tab bar, toolbar, pills), as in Health. Colour by meaning: the icon's blue (accent) for fitness and the plan, the track orange for running, pink for heart data
- Follow Apple HIG: SF Symbols only, Dynamic Type, system colors, standard navigation. A big custom size (hero numbers, artwork symbols) uses `.scaledFont(size:weight:design:)` from `Views/Design/ScaledFont.swift`, never a fixed `.font(.system(size:))`, so it follows the text-size setting; repeating or sliding animations respect `accessibilityReduceMotion`
- Support Dark Mode from day one; respect safe areas
- Minimal UI: one screen = one job. Don't stuff dashboards with stats.
- Accessibility: VoiceOver labels on interactive elements, sensible Dynamic Type behavior
- Brand colors/gradients are centralized in `PaceOff/Views/Design/`: `BrandPalette` (the icon's blues and track oranges, `BrandMark`), `TrackBend` (the icon's running track, drawn, plus the full-screen `BrandBackdrop`) and `BrandHero`. Reuse them, don't hardcode hex values in views

## Architecture
- Tabs: Today · History · Trends · Plan. Profile opens as a sheet from the avatar on Today, as in Health. The selected tab lives in `AppNavigation` (`@Observable`, in `RootView.swift`, injected with `.environment`), so a screen inside one tab can switch to another
- `PaceOffApp` owns the launch-flow state machine (`.splash → .auth → .onboarding → .main`, gated by `@AppStorage` flags in App Group defaults) and injects all services via `.environment(...)`
- Feature-based folder layout under `PaceOff/Views/` (one folder per screen or feature — e.g. `Views/Training/`, `Views/Onboarding/`, `Views/Legal/`, `Views/Design/`, `Views/Preview/`)
- Views stay dumb; `@MainActor @Observable` singletons own state and side effects:
  - `ProfileStore` — user identity, goal, PB, race date (single source of truth; the training-plan picker writes straight to it)
  - `TrainingPlanStore` — active plan, persisted as `training-plan.json`
  - `HealthKitService` — all HealthKit reads, background delivery via `HKObserverQuery`
  - `NotificationScheduler` — `UNUserNotificationCenter`, max three pushes/day, one-shot for today only (rules in `DailyPushPlanner`)
  - `BackgroundRefreshService` — `BGAppRefreshTask` (`com.paceoff.app.refresh`); registered in `PaceOffApp.init()` because iOS rejects registration after launch finishes. Each run re-syncs Health, recomputes the target, reconciles/retunes the training plan (`TrainingPlanReconciler`), and reschedules plan-aware notifications. A run whose Health read was kept out of the cache (locked phone, failed or empty read) changes nothing: no target, no retune, no rescheduled pushes.
  - `AppleSignInService`, `AppleIntelligenceCopy` (voice-line rewriter for the foreground refresh, nil-fallback to canned `VoiceCopy`; keeps accepted rewrites by their canned line)
  - `WatchWorkoutScheduler` — WorkoutKit: schedules the plan's next seven days of runs into Apple's Workout app on the watch, with pace alerts, behind the Plan tab's "Send workouts to Apple Watch" switch (App Group `sendWorkoutsToWatch`); every refresh and plan change schedules again, ending the plan or deleting the runner's data removes them
  - `TodayViewModel` — state container for the Today screen
- Pure algorithms live in `PaceOffShared` — `Sendable`, no I/O, unit-tested: `PushTargetEngine` (daily target, PRD §7), `TrainingPlanGenerator` + `VDOTCalculator` (both in `TrainingPlanGenerator.swift`; Daniels' formula closed-form, no lookup tables), `GoalPredictionService`, `ReadinessEngine` (daily green/yellow/red traffic light; its verdict feeds `PushTargetEngine` — red caps the day at 0.6× baseline, yellow holds baseline), `TrainingPlanReconciler` (today's plan-workout status + VDOT-drift pace retune for the background sync), `DailyPushPlanner` (which of the day's pushes go out, when, with what text), `HeartTrend` (the HRV and resting HR screens' daily values and baseline, on `ReadinessEngine`'s windows and thresholds), `WorkoutHeartRate` / `WorkoutElevation` (a run's heart rate over time and elevation gain, loss and profile, in `WorkoutProfile.swift`), `WeekReview` (the last seven days with each day's runs and plan workout, by `TrainingPlanReconciler`'s completion rule), `VoiceState` (which voice line a day gets; `VoiceCopy` holds the lines), `RunStreak` (consecutive running days, alive until the day is over) `BestEfforts` (a run's fastest 1 km, 5 km, 10 km and half marathon from its GPS route, the end interpolated between points, GPS jumps left out; and the bests kept across runs), `WatchSchedulePlanner` (which runs go to Apple Watch: the next seven days', today's as the day's prescription has it, no rest, strength-only or race days), `WorkoutBlocks` (a plan workout as the steps a watch runs: warm-up, repeated work and recovery, cool-down, each with its distance and pace band; quality sessions follow their notes), `SingleRunCap` (no prescribed run longer than 110% of the longest of the previous 30 days; applied to the daily target in `PushTargetEngine.target` and to today's plan run in `DayPrescription`), `DayPrescription` (the one prescription for today: the plan's workout as readiness changes it, rest on a plan rest day, the daily target without a plan workout), `NarrationCheck` (whether a model's rewording may replace a line: the same numbers, each as often, none added, within a length cap) and `RunWindowPlanner` (when in the day to run, from an hourly forecast: rain, heat or cold, wind and darkness avoided in that order, with the morning push's reason line)
- `HealthDataCache` (also `PaceOffShared`) is an **actor** that snapshots Health reads to `health-cache.json` so views render instantly on cold launch while a fresh sync runs. `HealthSyncDecision` (same file) decides whether a read may replace the snapshot: a locked or failed read never does, and an empty one only once the cache is over 3 days old
- HealthKit access is confined to `HealthKitService` (`@MainActor`) on iOS and `WorkoutSessionManager` on watchOS. Nothing else imports `HealthKit`.
- Watch app: `WorkoutSessionManager` drives `HKWorkoutSession` + `HKLiveWorkoutBuilder` with live running dynamics
- Preview support in `Views/Preview/PreviewSupport.swift`: sample data + `PreviewProfileStore`, gated behind `#if DEBUG`
- A language model phrases, it never decides. Every number and verdict a runner sees comes from a pure function; the on-device model may only reword that text, in the foreground, and the canned or template text is the fallback and the product on phones and in languages the model doesn't cover (`ARCHITECTURE.md`, "Rules for every model feature")

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

Regenerate the project after editing `project.yml`: `xcodegen generate` (the generated `.xcodeproj` is committed).

Every push to `main` also runs `.github/workflows/testflight.yml`: a Release device build, then, once the App Store Connect key's secrets exist, an archive uploaded to TestFlight (README: TestFlight).

**Cloud sessions have no Xcode, XcodeGen or Swift toolchain.** GitHub Actions CI (`.github/workflows/ci.yml`: build + `PaceOffTests` on a macOS runner) is the compiler there, so re-read a diff for build errors before pushing; `LOOP.md` § 4 has the checklist. Add a new Swift file to the project with `python3 scripts/pbxproj.py add <path> <target>…`, which makes the same edits XcodeGen would.

Do not run `xcodebuild test` in ad-hoc automation — it hangs on host device discovery in some environments. Run tests from Xcode (the `PaceOff` scheme's test action runs `PaceOffTests`). Test files compile `PaceOffShared` sources directly, so engine tests need no simulator-hosted app state.

## Scope discipline
The training-plan feature is **in scope** and shipping — a VDOT-based generator (`TrainingPlanGenerator`), a picker, a detail view, and a persistent active plan (`TrainingPlanStore`). Do not remove or gut it.

Anything that would require **CloudKit, a server, a paywall, Android, or a chat surface** is out of scope for the current milestone. `ROADMAP.md` tracks these under **Needs a decision** (D-08 to D-14), `ARCHITECTURE.md` says where each boundary runs, and `SPEC.md` keeps the older proposals under **V2+ / needs decision** — they are ideas, not commitments. Ask before starting one. Sending a runner's data to a third-party AI service belongs in the same list.

## Autonomous development
`ROADMAP.md` is the single queue of work, in priority order; `LOOP.md` is the procedure that takes its top item to a merged PR without the owner present. When running the loop:
- One roadmap item per PR, titled `[roadmap <ID>] …`, with the item's status updated in `ROADMAP.md` in the same PR.
- Never start an item with status `decision` or `blocked`; anything needing the owner's call becomes `blocked: <question>` rather than a guess.
- Items are merged by the loop only with green CI and a clean self-review. Since 2026-11-08 every item is `Merge: auto`: the owner doesn't approve PRs. A PR that touches entitlements, signing, privacy strings, legal or App Store copy, or removes a feature, says so in its title and the report.
- UI changes can't be seen from the cloud: list them in the roadmap's **Visual check queue**.
- A direct request from the owner always wins over the roadmap.

## Current priorities (2026-11)
- The goal: the number-one coach for runners with an iPhone and an Apple Watch. Pace Off owns the start of the day (what to run, and why) and the end (how it went, and what changes); Apple's Workout app records the run. `ARCHITECTURE.md` has the reasons.
- Work the roadmap top-down: Step 0 fixes (wrong advice, unsafe load) before Step 1 (one coach: on the wrist, adapting, explaining itself), before Step 2 (breadth), before Step 3 (race day).
- **iPhone-first**: onboarding, home, run detail, training plan, profile.
- **The plan reaches the wrist through WorkoutKit** and Apple's own Workout app (F-12), not through our watch app. The watchOS app stays deprioritized: the `PaceOff Watch App` target still builds and ships, but don't spend cycles polishing it, adding features, or reworking the workout session code unless the user explicitly asks. Bugfixes to keep it building are fine.
- Widget stays in scope but only as a "renders the cached target" surface — the WatchConnectivity-dependent in-progress-run state is on hold with the Watch work.
