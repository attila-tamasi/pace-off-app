# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is
iOS + watchOS running app. Reads runs, VO₂ max, HR from Apple Health, computes a daily push target, prescribes multi-week Daniels-VDOT training plans, and projects race times. One-liner: **"The running buddy that knows when to push you and when you need rest."**

No accounts (Sign in with Apple is optional). No servers. Privacy label: *Data Not Collected*.

Companion docs: `ROADMAP.md` (the prioritised backlog: what to build next), `LOOP.md` (how Claude works through the roadmap on its own), `SPEC.md` (shipped features + V2 proposals), `README.md` (build/run walkthrough), `Pace Off - PRD.docx` (full product spec — the PRD § references in code comments point here).

## Tech stack
- SwiftUI, Swift 6, iOS 26 / watchOS 26 minimum
- HealthKit for runs, VO₂ max, HR, running dynamics, dateOfBirth
- Modern Swift Observation framework (`@Observable`, `@Environment(Type.self)`) — **not** `ObservableObject`
- Swift Concurrency (async/await); no Combine unless unavoidable. `SWIFT_STRICT_CONCURRENCY` is currently `minimal` (MVP scaffold — to be tightened later).
- FoundationModels (Apple Intelligence, on-device) is used for optional voice-line rewrites — system framework, always behind `#if canImport` with a canned-copy fallback
- Persistence: App Group `UserDefaults` + small JSON files in the App Group container. **No SwiftData, no CoreData, no CloudKit, no third-party backend.**
- XcodeGen (`project.yml`) generates `PaceOff.xcodeproj` — regenerate after changing targets: `xcodegen generate`
- No third-party Swift packages in V1 unless explicitly agreed

## Targets & layout
Four targets defined in `project.yml`:
- `PaceOff` — iPhone app (sources: `PaceOff/`)
- `PaceOff Watch App` — watchOS companion (sources: `PaceOffWatch Watch App/` — note the folder name differs from the target name)
- `PaceOffWidget` — Lock Screen / Home Screen widget (reads the cached `RunTarget` JSON from App Group `UserDefaults`)
- `PaceOffTests` — XCTest suite (`PushTargetEngineTests`, `TrainingPlanGeneratorTests`, `TrainingPlanReconcilerTests`, `GoalPredictionServiceTests`, `HealthDataCacheTests`, `ReadinessEngineTests`, `DailyPushPlannerTests`); unit tests are cheap and expected

`PaceOffShared/` is **not a target** — it's a source folder compiled directly into every target above. Keep it free of UIKit, and free of HealthKit where avoidable, so it stays testable.

All targets read/write shared state through the `group.com.paceoff.app` App Group. Keys and the container URL live in `PaceOffShared/AppGroup.swift`. JSON files in the container: `training-plan.json` (active plan), `health-cache.json` (Health snapshot), `profile-photo.jpg`.

The app icon is one opaque 1024×1024 PNG, the same file in the iOS, widget and watch `AppIcon.appiconset`s. iOS derives the dark and tinted appearances. Don't build an icon from SF Symbols: their licence rules them out of app icons.

## Design rules
- iOS 26 **Liquid Glass** design language: prefer native materials (`.glassEffect`, `.background`, system backgrounds); never fake glass with manual blur/opacity hacks
- Screens read like Apple's Health app: large titles, data in `MetricCard`s (solid `secondarySystemGroupedBackground` cards with a coloured symbol + category, a big value, an optional mini chart). Glass stays on the navigation layer (tab bar, toolbar, pills), as in Health. Colour by meaning: the icon's blue (accent) for fitness and the plan, the track orange for running, pink for heart data
- Follow Apple HIG: SF Symbols only, Dynamic Type, system colors, standard navigation
- Support Dark Mode from day one; respect safe areas
- Minimal UI: one screen = one job. Don't stuff dashboards with stats.
- Accessibility: VoiceOver labels on interactive elements, sensible Dynamic Type behavior
- Brand colors/gradients are centralized in `PaceOff/Views/Design/`: `BrandPalette` (the icon's blues and track oranges, `BrandMark`), `TrackBend` (the icon's running track, drawn, plus the full-screen `BrandBackdrop`) and `BrandHero`. Reuse them, don't hardcode hex values in views

## Architecture
- Tabs: Today · History · Trends · Plan. Profile opens as a sheet from the avatar on Today, as in Health
- `PaceOffApp` owns the launch-flow state machine (`.splash → .auth → .onboarding → .main`, gated by `@AppStorage` flags in App Group defaults) and injects all services via `.environment(...)`
- Feature-based folder layout under `PaceOff/Views/` (one folder per screen or feature — e.g. `Views/Training/`, `Views/Onboarding/`, `Views/Legal/`, `Views/Design/`, `Views/Preview/`)
- Views stay dumb; `@MainActor @Observable` singletons own state and side effects:
  - `ProfileStore` — user identity, goal, PB, race date (single source of truth; the training-plan picker writes straight to it)
  - `TrainingPlanStore` — active plan, persisted as `training-plan.json`
  - `HealthKitService` — all HealthKit reads, background delivery via `HKObserverQuery`
  - `NotificationScheduler` — `UNUserNotificationCenter`, max three pushes/day, one-shot for today only (rules in `DailyPushPlanner`)
  - `BackgroundRefreshService` — `BGAppRefreshTask` (`com.paceoff.app.refresh`); registered in `PaceOffApp.init()` because iOS rejects registration after launch finishes. Each run re-syncs Health, recomputes the target, reconciles/retunes the training plan (`TrainingPlanReconciler`), and reschedules plan-aware notifications.
  - `AppleSignInService`, `AppleIntelligenceCopy` (voice-line rewriter, nil-fallback to canned `VoiceCopy`)
  - `TodayViewModel` — state container for the Today screen
- Pure algorithms live in `PaceOffShared` — `Sendable`, no I/O, unit-tested: `PushTargetEngine` (daily target, PRD §7), `TrainingPlanGenerator` + `VDOTCalculator` (both in `TrainingPlanGenerator.swift`; Daniels' formula closed-form, no lookup tables), `GoalPredictionService`, `ReadinessEngine` (daily green/yellow/red traffic light; its verdict feeds `PushTargetEngine` — red caps the day at 0.6× baseline, yellow holds baseline), `TrainingPlanReconciler` (today's plan-workout status + VDOT-drift pace retune for the background sync), `DailyPushPlanner` (which of the day's pushes go out, when, with what text)
- `HealthDataCache` (also `PaceOffShared`) is an **actor** that snapshots Health reads to `health-cache.json` so views render instantly on cold launch while a fresh sync runs
- HealthKit access is confined to `HealthKitService` (`@MainActor`) on iOS and `WorkoutSessionManager` on watchOS. Nothing else imports `HealthKit`.
- Watch app: `WorkoutSessionManager` drives `HKWorkoutSession` + `HKLiveWorkoutBuilder` with live running dynamics
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

Regenerate the project after editing `project.yml`: `xcodegen generate` (the generated `.xcodeproj` is committed).

**Cloud sessions have no Xcode, XcodeGen or Swift toolchain.** GitHub Actions CI (`.github/workflows/ci.yml`: build + `PaceOffTests` on a macOS runner) is the compiler there, so re-read a diff for build errors before pushing; `LOOP.md` § 4 has the checklist. Add a new Swift file to the project with `python3 scripts/pbxproj.py add <path> <target>…`, which makes the same edits XcodeGen would.

Do not run `xcodebuild test` in ad-hoc automation — it hangs on host device discovery in some environments. Run tests from Xcode (the `PaceOff` scheme's test action runs `PaceOffTests`). Test files compile `PaceOffShared` sources directly, so engine tests need no simulator-hosted app state.

## Scope discipline
The training-plan feature is **in scope** and shipping — a VDOT-based generator (`TrainingPlanGenerator`), a picker, a detail view, and a persistent active plan (`TrainingPlanStore`). Do not remove or gut it.

Anything that would require **CloudKit, a server, a paywall, Android, or a chat surface** is out of scope for the current milestone. `SPEC.md` lists proposals that fall in these categories under a **V2+ / needs decision** section — they are ideas, not commitments. Ask before starting one.

## Autonomous development
`ROADMAP.md` is the single queue of work, in priority order; `LOOP.md` is the procedure that takes its top item to a merged PR without the owner present. When running the loop:
- One roadmap item per PR, titled `[roadmap <ID>] …`, with the item's status updated in `ROADMAP.md` in the same PR.
- Never start an item with status `decision` or `blocked`; anything needing the owner's call becomes `blocked: <question>` rather than a guess.
- Only `Merge: auto` items are merged by the loop, and only with green CI and a clean self-review. `Merge: review` items wait for the owner.
- UI changes can't be seen from the cloud: list them in the roadmap's **Visual check queue**.
- A direct request from the owner always wins over the roadmap.

## Current priorities (2026-10)
- Work the roadmap top-down: Wave 1 fixes (wrong advice, unsafe load, stale data) before Wave 2 quality, before Wave 3 features.
- **iPhone-first**: onboarding, home, run detail, training plan, profile.
- **watchOS app is deprioritized** for the current wave. The `PaceOff Watch App` target still builds and ships, but don't spend cycles polishing it, adding features, or reworking the workout session code unless the user explicitly asks. Bugfixes to keep it building are fine.
- Widget stays in scope but only as a "renders the cached target" surface — the WatchConnectivity-dependent in-progress-run state is on hold with the Watch work.
