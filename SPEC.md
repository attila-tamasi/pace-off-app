# Pace Off — Spec

Living spec. Split into **shipped today** (what exists in the codebase now) and **proposals** (brainstorm ideas awaiting a decision, tagged with the cost they'd carry). See `CLAUDE.md` for working principles.

---

## Shipped today

### 1. Splash + auth gate
- Native launch screen → animated splash (`SplashView`) → routes to onboarding on first run, `AuthGateView` if the user chose to sign in, otherwise `RootView`
- Sign in with Apple is optional (`AppleSignInService`). It asks only for the name (`.fullName`), never the email, and stores Apple's app-scoped user ID and the name on the device

### 2. Onboarding
- Short flow: value prop → HealthKit permission → weekly cadence + goal setup
- HealthKit read access: workouts, VO₂ max, resting HR, running dynamics, date of birth
- Notification permission requested at the end; "Not now" moves on without asking iOS. The app works the same without it (the pushes just don't show), "Not now" leaves the Profile "Daily pushes" switch off, and turning it on asks iOS then

### Accessibility
- Every text size follows Dynamic Type: text styles, and `.scaledFont(size:)` (a `@ScaledMetric` size relative to the nearest text style) for the big hero numbers and artwork symbols. Icon-only controls carry VoiceOver labels. Under Reduce Motion the notifications bell stops wiggling, and the onboarding hero and the done check fade in instead of sliding or bouncing

### 3. Today — daily push target
- `TodayView` shows the day's prescribed run distance + tone (drill-sergeant / etc.), the reasoning behind it, and an "already ran" card when applicable, in Health-style cards with mini charts for HRV, resting HR, VO₂ max and the last seven days' distance
- The voice line (`VoiceState` → `VoiceCopy`) names a skip only when a day was actually missed: a run yesterday gets a streak line, and a run today ends the pushing for the day unless it falls short of the plan's workout. The engine's restart and recovery tones pick restart and rest copy, so the line never fights the tone badge. The streak counts through yesterday until today's run is in
- **No runs yet** (a new runner, or Health access denied): there's no target and no pushes. Today shows a "Log your first run" card in the hero's place: what Pace Off needs, how to record a run, and where in the Health app to let Pace Off read workouts (HealthKit never says whether read access was denied, so the hint is always there), with an "Open Health" button. `PushTargetEngine.target` returns nil until a Health read has held a run (App Group `hasSeenRun`); the foreground and background refreshes then clear the day's pushes and do nothing else. A runner seen before, back after more than the 90-day window, gets the restart target as before. With a plan active, the card still shows today's plan workout
- Distance and tone come from `PushTargetEngine` — a pure Swift algorithm in `PaceOffShared` (PRD §7). Inputs: 90 days of runs, 90 days of VO₂ max, 14 days of resting HR. Output: `RunTarget` (distance, tone, reasoning).
- **VO₂ max trend** (`PushTargetEngine.vo2MaxTrend`) — read from the last 28 days only once there are at least 3 readings spanning 14 days or more. A linear fit counts as falling or rising only when its change over the window is at least 0.25 ml/kg/min and its slope is two standard errors from flat, the error never taken below what a 0.2 ml/kg/min wobble per reading gives (so three readings that happen to line up don't make a trend); anything less is a plateau, unless the readings scatter more than 0.5 around their line, which is too noisy to read. Falling: +15%, aggressive. Plateau: +10%, firm. Rising: hold the baseline. Too little data or too noisy: no effect. The "VO₂ max declining" voice line uses the same reading. The VO₂ max screen's trend line and copy read the same function
- The day's distance never exceeds its cap: the 1.4× hard ceiling on every day, restart days included (a restart still gets the 3 km floor when the ceiling sits under it), or a lower cap when the resting-HR guard (1.0×), a post-long-run recovery day (0.6×) or readiness (yellow 1.0×, red 0.6×) applies. The target shows in whole km, rounded up only while that stays within the cap (a 3.1 km red day shows 3 km), and "target hit" is judged against the shown value
- Voice-line copy lives in `VoiceCopy.swift`; tone selection in `Tone.swift`
- Result is written to App Group `UserDefaults` so the Watch app and widget render instantly

### 4. Training plan (Daniels VDOT)
- **Picker** (`TrainingPlanPickerView`) — race distance (5K / 10K / Half / Marathon), optional race day, long-run day, and three intensity tiers (Easy / Medium / Aggressive)
- **Generator** (`TrainingPlanGenerator`) — pure Swift, VDOT-anchored paces via `VDOTCalculator` (Daniels' formula, closed-form; no lookup tables). The VDOT comes from Health's VO₂ max, else the PB over its own distance (a PB stores its distance, so a 10K PB anchors a marathon plan as well). A value outside 10–90 is a bad sample or a typo and is ignored; of the rest, the first inside the formula's 20–90 range wins, and a slow one (10–20) is raised to 20 rather than replaced. The beginner default (38) applies only when there's no usable measurement. Handles quality-day spacing, taper, race-date shrink. Weekly distance rises at most 10% a week, so a plan shortened by a race date builds as far as that allows and peaks lower, instead of jumping
- **Week 1 starts from the runner** — its long run goes at most 10% past the longest run of the last four weeks in Health, never under 40% of the plan's peak week, and at most the usual 70%. Without a Health snapshot it's 70%. A plan that starts low climbs by the same 10% rule, so a short plan peaks lower
- **Race day** — with a race date the plan can reach, the race (`WorkoutKind.race`, the goal distance, no pace band) is the plan's last day. The plan counts its weeks back from it (`TrainingPlan.startDate`), so the taper weeks line up with the race whatever its weekday, and week 1 can begin a few days before the plan was made. The day before the race is rest, and the two days before that carry no quality session or long run. The Plan tab and Today's plan line show it as "Race day". On the day, the only push is about the race ("Race day · 21.1 km. …"), with no target and no reminders, and the widget shows the same line. A race further out than the goal's default plan length (16 weeks marathon, 12 half, 10 10K, 8 5K) starts the plan later, so it still ends on race day: until week 1 the Plan tab says when it starts and previews the first week, Today shows its daily target without a plan line, and each background sync rebuilds the plan from current data (paces and week 1, for the same race day) without a push; the paces-only retune and its push start with week 1
- **Long run share** — the long run takes at most 45% of the week with three runs, 35% with four, 30% with five. Each goal has a long-run benchmark (5K 8–10 km, 10K 14–16, half 20–24, marathon 37), cut to that share of the peak week; the distance it gives up goes to the easy runs, so the week's total stays the same. Marathon long runs peak at 20.3 / 22.3 / 25.5 km (Easy / Medium / Aggressive), the half's at 15.8 / 18.0 / 21.3 km. A plan shortened by a race date peaks lower (see the 10% rule above)
- **Detail** (`TrainingPlanDetailView`) — week-by-week preview + "Select this plan" activates it
- **Store** (`TrainingPlanStore`) — persists the active plan as JSON in the App Group container; observable via `@Observable`
- **Settings sheet** (`TrainingPlanSettingsView`) — inspect / end the active plan
- Goal + race date are edited on the picker and written straight to `ProfileStore` (single source of truth — same values drive the Profile prediction card and the Today screen)

### 5. Race-time projection
- `GoalPredictionService` predicts a realistic finish time for the user's goal, given recent runs, VO₂ max history, PB, and race date
- Surfaced on the Profile screen with confidence, gap-to-PB, projected training improvement, and age-graded equivalent
- **The PB and its distance** — a PB records the distance it was run over (the onboarding and profile editors ask for it, the goal's by default). A PB for another distance is converted through VDOT to the goal's (Daniels' equivalent performance, `VDOTCalculator.raceTimeSeconds`), never used as a time for the goal; the gap to PB shows only for a PB over the goal's own distance. A PB no one could run (a 0:00, a typo) is never used. A profile saved before PBs had a distance gives its PB the goal's distance when it loads, but only if the time is plausible there (a 45:00 saved under a 10K goal and loaded under a half goal isn't a half time): otherwise the distance stays unknown, the PB isn't used, and Profile asks the runner to set it

### 6. History + Trends + VO₂ max detail
- `HistoryView` — list of past runs from Health
- `RunDetailView` — opened from History, Today's run and Last run: the route, then every figure Health recorded (start–end time, duration, pace, speed, heart rate average / max / min, energy, elevation gain and loss, steps, weather, indoor or outdoor, METs), heart rate over time, the elevation profile, per-km splits with pace, heart rate and elapsed time, and running dynamics. A figure Health didn't record is left out
- `TrendsView` — weekly mileage + pace charts
- Trends: VO₂ max (28 days), weekly distance (12 weeks) and pace (28 days) cards, each with a line saying what's missing when it has nothing to draw
- `VO2MaxDetailView` — 12-month VO₂ max chart; its trend line and "what it means" copy say what today's target does with the trend
- `WeekDetailView` — opened from Today's Last 7 days card: the week's distance and streak, a bar per day with the plan's distance dashed across it, sessions done and distance against the plan with a button to the Plan tab, and each day with its plan workout (done, still to do, missed or rest) and its runs, which open their detail (`WeekReview` in `PaceOffShared`)
- `HeartTrendDetailView` — HRV and resting heart rate, opened from their Today cards: the latest reading against the baseline the readiness card uses (30-day HRV, 14-day resting HR), a Week / Month / 3 Months chart with the baseline marked, the readiness thresholds, and what the number means (`HeartTrend` in `PaceOffShared`)

### 7. Watch app
- `WatchTodayView` mirrors today's push target
- Live workout via `HKWorkoutSession` + `HKLiveWorkoutBuilder` (running dynamics: power, stride, vertical oscillation, ground contact, cadence)
- Post-run summary + write-back to Health

### 8. Widget
- Lock Screen + Home Screen widget rendering today's target from the shared App Group snapshot
- Plan-aware: shows today's plan workout (summary + ✓ when completed); planned rest days keep the status dot green instead of the after-noon red nag
- After a fresh Health read, the foreground refresh and the background sync write the day in one go (`WidgetCache`: target, voice line, ran today, plan workout) and reload the widget's timeline, so a run shows within a refresh, not an hour later. A read that kept the cache writes nothing, and a day computed later is never overwritten by an earlier one
- The timeline has entries at noon (the dot turns red) and at midnight. A day cached on an earlier date renders as "Open Pace Off" with a grey dot and no voice line, never as today's
- Time-of-day-based status dot; no live "in-progress run" state yet

### 9. Profile + preferences
- Identity hero (photo, name, age), goal + PB + prediction card, active training-plan card, notification / voice / health preferences. Each fact appears once: the goal, PB and race-day countdown live only in the goal card. The prediction is worked out again when the goal, race day, PB or birthday changes, or when a fresh Health read lands
- Legal (T&C, Privacy, licenses), delete-my-data path, sign-out
- Notifications: a "Daily pushes" switch (App Group `notificationsEnabled`, on until turned off) and the morning / afternoon / evening times, shown as they fire (the afternoon push at half past its hour, from `DailyPushPlanner.Schedule.time(of:)`). A change reschedules today's pushes at once, from the day's last scheduling inputs when they're today's, else from a fresh refresh. Turning the switch on when iOS was never asked ("Not now" in onboarding sets it off) asks then; when iOS was told no, Profile points to Settings. With the switch off, nothing is scheduled and pending notices go, the plan-retune one included

### 10. Notifications
- `NotificationScheduler` uses `UNUserNotificationCenter`; up to three pushes / day per PRD §9.1. `DailyPushPlanner` (in `PaceOffShared`, unit-tested) decides which go out, when and with what text
- Each push is a one-shot for today's date, scheduled only while its time is still ahead; the foreground refresh and the background task schedule each day afresh, so one day's text never repeats on the next. A next-morning push covers a night with no refresh: it names tomorrow's plan workout, or just says a new target is waiting, and the next refresh replaces it
- Once today is done (the plan workout completed, or any run on a day without a plan workout), nothing more goes out today; a short run doesn't tick off a planned workout. On a planned rest day only the morning rest note goes out
- Evening "last call" only fires when the user has skipped at least one day this week (Monday-based week; planned rest days aren't skips)
- Nothing is scheduled before onboarding completes, and sign-out or "Delete my data" removes every pending and delivered push

### 11. Daily readiness traffic light
- Green / Yellow / Red readiness card on Today; it opens `ReadinessDetailView`, which shows each signal against its baseline with its own grade (each opening its `HeartTrendDetailView`), how the two combine, and what each colour does to the target — HRV (SDNN) + resting HR versus rolling personal baselines (30-day HRV, 14-day RHR), with one supporting sentence ("HRV below your baseline — easy day.")
- `ReadinessEngine` — pure Swift in `PaceOffShared`, unit-tested; two independently degraded signals escalate to red; hides entirely (returns nil) until ≥7 days of HRV or ≥5 days of RHR history
- **Feeds the push target** (since the readiness-integration follow-up): red caps the day at 0.6× baseline and shifts tone to recovery; yellow refuses to push above baseline and softens an aggressive tone; green/unknown changes nothing. `RunTarget.readinessCapApplied` records when the cap fired.
- HRV series cached in `HealthDataSnapshot` (schema v2); no new HealthKit read scope — SDNN was already requested for the morning check-in card

### 12. Background plan sync
- **Health observers** — at launch (once onboarding has asked for Health access) `HKObserverQuery`s on running workouts (immediate background delivery) and VO₂ max (hourly) start; if background delivery can't be enabled (no Health access yet) they're set up again on a later call. A new run or reading wakes the app, in the background, for the same refresh the scheduled background task runs, under a background-time assertion: re-sync, target, plan, today's pushes rescheduled, widget reloaded, so a finished run stops the afternoon reminder without opening the app. A delivery during a refresh makes it go round once more. One that finds the phone locked reads nothing and isn't acknowledged, so HealthKit delivers it again once a read can get through. In the foreground nothing runs: the app refreshes when it becomes active. Signed out, a refresh does nothing at all. When iOS expires the background task, its work is cancelled and the task is reported complete (failed) from the expiration handler, once, whichever ends first
- The existing `BGAppRefreshTask` (~4×/day) now reconciles the active training plan against each fresh Health download, via `TrainingPlanReconciler` (pure Swift in `PaceOffShared`, unit-tested)
- **Today's workout status** — did a recorded run cover ≥85% of today's prescription? Cached to App Group defaults (`lastPlanWorkoutSummary`, `planWorkoutCompletedToday`) for the widget / cold launch
- **Pace retune** — when the runner's current VDOT (fresh VO₂ max or PB, resolved exactly like the plan picker) drifts ≥1.0 from the plan's anchor, the *remaining* weeks' pace bands are recomputed; past weeks, structure, and distances never change; the user gets a one-shot "plan retuned" notification. A beginner-default plan retunes on the first real VDOT. Only a fresh Health read retunes: on a locked phone, or when a read fails or comes back empty, the sync keeps the cached snapshot and the background run changes nothing (no target, no retune, no retune notification, no rescheduled pushes; the next-morning push covers the night).
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
- "Delete my data" (Profile, below Sign Out, with a confirmation) — erases every App Group key (`AppGroup.keyPrefix`) and container file (`AppGroup.containerFiles`: plan, Health snapshot, photo), cancels every scheduled and delivered push, reloads the widget (it then shows "Open Pace Off") and returns to the start. Apple Health keeps its data. Sign-out does exactly the same.
- With **B** (CloudKit) the delete would also have to reach the cloud copy; that part isn't built, since nothing leaves the device today.
- **Cost:** part of the CloudKit adoption in **B**.

### F. Notes on scope
Explicitly **out of scope** for the current milestone unless the user explicitly opens the door:
- ACWR trend surface
- watchOS complications
- Social feed
- In-app chat
- Android client
- Subscriptions / paywall
