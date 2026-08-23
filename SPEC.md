# Pace Off — Spec

Living spec. Split into **shipped today** (what exists in the codebase now) and **proposals** (brainstorm ideas awaiting a decision, tagged with the cost they'd carry). See `CLAUDE.md` for working principles.

---

## Shipped today

### 1. Splash + auth gate
- Native launch screen → animated splash (`SplashView`) → routes to onboarding on first run, `AuthGateView` if the user chose to sign in, otherwise `RootView`
- Sign in with Apple is optional (`AppleSignInService`)

### 2. Onboarding
- Short flow: value prop → HealthKit permission → weekly cadence + goal setup
- HealthKit read access: workouts, VO₂ max, resting HR, running dynamics, date of birth
- Notification permission requested at the end

### 3. Today — daily push target
- `TodayView` shows the day's prescribed run distance + tone (drill-sergeant / etc.), the reasoning behind it, and an "already ran" card when applicable
- Distance and tone come from `PushTargetEngine` — a pure Swift algorithm in `PaceOffShared` (PRD §7). Inputs: 90 days of runs, 90 days of VO₂ max, 14 days of resting HR. Output: `RunTarget` (distance, tone, reasoning).
- Voice-line copy lives in `VoiceCopy.swift`; tone selection in `Tone.swift`
- Result is written to App Group `UserDefaults` so the Watch app and widget render instantly

### 4. Training plan (Daniels VDOT)
- **Picker** (`TrainingPlanPickerView`) — race distance (5K / 10K / Half / Marathon), optional race day, long-run day, and three intensity tiers (Easy / Medium / Aggressive)
- **Generator** (`TrainingPlanGenerator`) — pure Swift, VDOT-anchored paces via `VDOTCalculator` (Daniels' formula, closed-form; no lookup tables). Handles quality-day spacing, taper, race-date shrink
- **Marathon peak long run** — 37 km across all tiers
- **Detail** (`TrainingPlanDetailView`) — week-by-week preview + "Select this plan" activates it
- **Store** (`TrainingPlanStore`) — persists the active plan as JSON in the App Group container; observable via `@Observable`
- **Settings sheet** (`TrainingPlanSettingsView`) — inspect / end the active plan
- Goal + race date are edited on the picker and written straight to `ProfileStore` (single source of truth — same values drive the Profile prediction card and the Today screen)

### 5. Race-time projection
- `GoalPredictionService` predicts a realistic finish time for the user's goal, given recent runs, VO₂ max history, PB, and race date
- Surfaced on the Profile screen with confidence, gap-to-PB, projected training improvement, and age-graded equivalent

### 6. History + Trends + VO₂ max detail
- `HistoryView` — list of past runs from Health
- `TrendsView` — weekly mileage + pace charts
- `VO2MaxDetailView` — 12-month VO₂ max chart

### 7. Watch app
- `WatchTodayView` mirrors today's push target
- Live workout via `HKWorkoutSession` + `HKLiveWorkoutBuilder` (running dynamics: power, stride, vertical oscillation, ground contact, cadence)
- Post-run summary + write-back to Health

### 8. Widget
- Lock Screen + Home Screen widget rendering today's target from the shared App Group snapshot
- Plan-aware: shows today's plan workout (summary + ✓ when completed) from the background-sync cache; planned rest days keep the status dot green instead of the after-noon red nag
- Time-of-day-based accent color; no live "in-progress run" state yet

### 9. Profile + preferences
- Identity hero, goal + PB + prediction card, active training-plan card, notification / voice / health preferences
- Legal (T&C, Privacy, licenses), delete-my-data path, sign-out
- Notification hour tuning (morning / afternoon / evening)

### 10. Notifications
- `NotificationScheduler` uses `UNUserNotificationCenter` + calendar triggers; up to three pushes / day per PRD §9.1
- Evening "last call" only fires when the user has skipped at least one day this week

### 11. Daily readiness traffic light
- Green / Yellow / Red readiness card on Today — HRV (SDNN) + resting HR versus rolling personal baselines (30-day HRV, 14-day RHR), with one supporting sentence ("HRV below your baseline — easy day.")
- `ReadinessEngine` — pure Swift in `PaceOffShared`, unit-tested; two independently degraded signals escalate to red; hides entirely (returns nil) until ≥7 days of HRV or ≥5 days of RHR history
- **Feeds the push target** (since the readiness-integration follow-up): red caps the day at 0.6× baseline and shifts tone to recovery; yellow refuses to push above baseline and softens an aggressive tone; green/unknown changes nothing. `RunTarget.readinessCapApplied` records when the cap fired.
- HRV series cached in `HealthDataSnapshot` (schema v2); no new HealthKit read scope — SDNN was already requested for the morning check-in card

### 12. Background plan sync
- The existing `BGAppRefreshTask` (~4×/day) now reconciles the active training plan against each fresh Health download, via `TrainingPlanReconciler` (pure Swift in `PaceOffShared`, unit-tested)
- **Today's workout status** — did a recorded run cover ≥85% of today's prescription? Cached to App Group defaults (`lastPlanWorkoutSummary`, `planWorkoutCompletedToday`) for the widget / cold launch
- **Pace retune** — when the runner's current VDOT (fresh VO₂ max or PB, resolved exactly like the plan picker) drifts ≥1.0 from the plan's anchor, the *remaining* weeks' pace bands are recomputed; past weeks, structure, and distances never change; the user gets a one-shot "plan retuned" notification. A beginner-default plan retunes on the first real VDOT.
- **Plan-aware notifications** — morning/afternoon pushes lead with today's prescribed workout; planned rest days suppress the reminder and "last call" nags; a completed plan workout silences the rest of the day. Foreground refresh (`TodayViewModel`) applies the same logic so the two paths never disagree.

---

## Proposals — V2+ / needs decision

Everything below came out of a brainstorm and would extend Pace Off's positioning toward accountability. **None of these are approved.** Each is tagged with the dependency cost so a decision can be made deliberately.

### A. Daily traffic-light (HRV + resting HR) — ✅ shipped
Shipped as **§11** above (decision: augments the tone display). The follow-up question — should a red day cap the prescribed distance? — was answered **yes**: readiness now feeds `PushTargetEngine` (see §11).

### B. Buddy pairing + shared weekly goal progress
- Invite a running buddy via share link (iMessage flow); no random matching
- Both see each other's *counts only* — did you hit 2 / 3 runs this week — never run details
- Unpair path
- **Cost:** requires **CloudKit** (CKShare for the pair, private database per user + shared zone). CloudKit is currently not a dependency; adding it changes the privacy label from *Data Not Collected* and requires an iCloud account for buddy features. Users without iCloud must keep the app fully functional in solo mode.

### C. Accountability push notifications
- If the week is slipping vs. the shared weekly goal, buddy receives a push ("Attila hasn't run yet this week 👀")
- User picks a tone per relationship: cheeky / gentle / off — respected always
- **Cost:** CloudKit subscriptions (or APNs with a lightweight fan-out). Depends on **B**.

### D. Weekly summary
- Sunday-evening push + a summary screen: did you hit your goal, did your buddy
- Streak count (consecutive successful weeks) surfaced on Profile
- **Cost:** streak state persists to App Group; buddy-side of the summary depends on **B**.

### E. Data-management + legal
- "Delete my data" — CloudKit + local wipe (App Store requirement if we ship **B**)
- Currently we only wipe local state on sign-out; a CloudKit-aware delete needs building.
- **Cost:** part of the CloudKit adoption in **B**.

### F. Notes on scope
Explicitly **out of scope** for the current milestone unless the user explicitly opens the door:
- ACWR trend surface
- watchOS complications
- Social feed
- In-app chat
- Android client
- Subscriptions / paywall
