# Pace Off — Roadmap

The backlog the roadmap loop works through, in priority order. `LOOP.md` is the procedure; this file is the queue. Edit it freely: reorder items, add new ones, set a status. The loop reads it fresh on every run, and the topmost workable item always wins.

The items come from the full code review of 2026-10-18, re-checked against the source on 2026-10-29. Line numbers drift: treat **Where** as a starting point and confirm the problem in the code before changing anything.

## How items work

```
### R-01 · Short title
- **Status:** todo
- **Size:** S | M | L   ·   **Merge:** auto | review
- **Problem:** what is wrong today, from the runner's point of view.
- **Where:** files and symbols to start from.
- **Done when:** the acceptance criteria. Every bullet must hold before the item is done.
```

**Status** is one of:

| Status | Meaning | The loop… |
|---|---|---|
| `todo` | Ready to build | picks the first one, top to bottom |
| `in progress (PR #n)` | A PR is open for it | finishes that PR before starting anything new |
| `done (PR #n)` | Merged | skips it |
| `blocked: <reason>` | Tried and stuck | skips it until a person edits the reason away |
| `decision` | Needs the owner's call | never touches it |

**Merge:** `auto` items are merged by the loop once CI is green and its own review is clean. `review` items get a PR and wait for the owner: legal text, entitlements, App Store-facing copy, or anything that removes a feature.

**Size:** S is a few lines to one file, M is one feature across a few files, L is several PRs. The loop splits an L item into sub-items (`R-05a`, `R-05b`…) in this file before starting it.

---

## Wave 1 · Fixes (critical)

These tell the runner the wrong thing or prescribe too much load. They go before any new feature.

### R-01 · Notifications repeat one day's content
- **Status:** done (PR #19)
- **Size:** M   ·   **Merge:** auto
- **Problem:** The three daily pushes use repeating calendar triggers, but their text is that day's target and workout. If the app isn't opened, the same text comes for days, and the pushes keep coming after sign-out. The evening "Last call" fires on every evening without a run today, not only after a skipped day.
- **Where:** `PaceOff/Services/NotificationScheduler.swift` (`schedule(id:hour:minute:…)` builds `UNCalendarNotificationTrigger(…, repeats: true)`; the evening condition in `scheduleDailyPushes`); `ProfileStore.signOut()`.
- **Done when:**
  - Each push is a one-shot for today's date. Slots that have already passed today are not scheduled. The foreground refresh and the background task reschedule them.
  - Sign-out removes all pending and delivered Pace Off notifications.
  - "Last call" fires only when at least one day this week was skipped, as the Profile copy promises.
  - The slot decision (which pushes, at which times, with which text) is a pure function in `PaceOffShared` with unit tests.

### R-02 · "You skipped yesterday" to runners who ran
- **Status:** done (PR #20)
- **Size:** S   ·   **Merge:** auto
- **Problem:** The voice line treats "ran yesterday" as a skip, so a daily runner gets "You skipped yesterday" every morning. It also ignores recovery and red days: next to a RECOVERY badge it says the run is mandatory. On day 7 of a streak it says "Day 8".
- **Where:** `PaceOffShared/VoiceCopy.swift` (`todayCard`, the `switch target.daysSinceLastRun`); compare with how `PushTargetEngine` counts `daysSinceLastRun`.
- **Done when:**
  - Copy matches the engine's meaning of `daysSinceLastRun`.
  - Ran yesterday is never called a skip.
  - Recovery tone and red readiness get rest-appropriate copy.
  - The streak day number is right.
  - New `VoiceCopyTests` cover each case.

### R-03 · Locked-phone background refresh overwrites good data with empty
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** At night on a locked phone, HealthKit reads fail or come back empty, and the sync saves that empty result over the good cache. The next target is then a restart day, and a false "Training plan retuned" push goes out.
- **Where:** `HealthKitService.syncAll()` (saves the snapshot); `BackgroundRefreshService`; `HealthDataCache`.
- **Done when:**
  - When protected data is unavailable, or a read fails or returns nothing while the cache has data, the cache is kept, and no retune or plan notification is sent from that run.
  - The accept-or-keep rule is a pure function with tests in `HealthDataCacheTests`.

### R-04 · The daily target escapes its bounds
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:**
  - A restart day has no upper limit: with a 5 km baseline it can still come out at 21 km.
  - Rounding up for display breaks the other limits too. A red day shows 4 km instead of 3, and the 1.4× ceiling shows as 1.5×.
- **Where:** `PaceOffShared/PushTargetEngine.swift` (restart branch; the hard-ceiling step skips `.restart`); `RunTarget.displayedDistanceKm` (`ceil`).
- **Done when:**
  - Restart days are capped.
  - The displayed whole-km value never exceeds the cap that produced it, whether that's the red-day 0.6×, the ceiling, or the restart cap.
  - The "target hit" comparison still uses the displayed value.
  - `PushTargetEngineTests` cover a 5 km-baseline restart, a red day and a ceiling-clamped day.

### R-05 · Easy marathon plan: long run is most of the week
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** In the Easy marathon plan, the long run is 82% of weekly distance, already 25.9 km in week 1, even for a beginner.
- **Where:** `PaceOffShared/TrainingPlanGenerator.swift` (week templates, long-run share).
- **Done when:**
  - The long run is at most about 30% of the week's distance, in every tier and goal.
  - The week-1 long run scales from current fitness (recent long runs or VDOT).
  - Tests assert both for every goal × tier.

### R-06 · Race-date plans jump in volume
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** When a race date shortens the plan, week 2 is +43% on week 1.
- **Where:** `TrainingPlanGenerator.planWeeks(for:goalDate:)` and the volume ramp.
- **Done when:**
  - Week-over-week distance rises by at most about 10%, cutback weeks excepted, including in compressed plans.
  - Tests cover goal dates from 4 to 20 weeks out.

### R-07 · The race isn't in the plan
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** On race day the plan prescribes a 6 km long run, with intervals two days later.
- **Where:** `TrainingPlanGenerator`; `WorkoutKind`; how the Plan tab, Today and notifications show the day.
- **Done when:**
  - The goal date appears in the plan as the race.
  - The days before it taper, and the days after it are rest or easy.
  - The Plan tab, Today's plan line and the notifications name it as race day.
  - Tests cover it.

### R-08 · Slow runners get paces that are too fast
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** Below VDOT 25 the generator falls back to the beginner default of 38, so it prescribes paces far faster than the runner can hold.
- **Where:** `TrainingPlanGenerator` (`beginnerVDOTFallback` and the VDOT source order); `VDOTCalculator` validity range.
- **Done when:**
  - A measured VDOT below 25 is used as is, clamped only to the formula's valid range.
  - The fallback applies only when there's no measurement at all.
  - Tests cover VDOT 20, 25 and 38.

### R-09 · The widget shows stale data
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** The app never asks WidgetKit to reload, so after a run the widget can stay red for up to an hour. After midnight it shows yesterday's target with a green dot.
- **Where:** nothing calls `WidgetCenter.shared.reloadAllTimelines()`; `TodayViewModel.refresh()`, `BackgroundRefreshService`, `PaceOffWidget.swift` (`PaceOffProvider`).
- **Done when:**
  - The app reloads timelines after writing the target or plan status.
  - The widget timeline has an entry at the next midnight.
  - A target computed on an earlier day renders as "Open Pace Off" with a neutral dot, not as today's.

---

## Wave 2 · Quality

### Q-01 · Notification "Not now" asks for permission anyway
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** On the onboarding notifications step, "Not now" triggers the same system prompt as "Allow".
- **Where:** `PaceOff/Views/Onboarding/OnboardingFlow.swift` (`secondaryTitle: "Not now"`, `onSecondary: { … onAllow() }`).
- **Done when:** "Not now" moves on without requesting authorization, and the app still works without it.

### Q-02 · Sign in asks for an email it never uses
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** Sign in with Apple requests the email scope, but nothing uses it.
- **Where:** `PaceOff/Views/AuthGateView.swift` (`requestedScopes = [.fullName, .email]`).
- **Done when:** only `.fullName` is requested, and nothing reads an email.

### Q-03 · No empty state for a new runner
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** With no runs, or with Health access denied, Today shows a 3 km restart target and a skip count, and the evening "Last call" fires.
- **Where:** `TodayViewModel`, `TodayView`, `PushTargetEngine` with zero runs, `NotificationScheduler`.
- **Done when:**
  - With no runs, Today shows a first-run card: what Pace Off needs and how to log a first run, with a link to Health settings when access is denied.
  - There is no target and no pushes until there is data.
  - Tests cover the engine's no-data case.

### Q-04 · The PB isn't tied to a distance
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** When the goal changes, the old PB stays, so a 10K time is used as a half-marathon time in the prediction and the plan paces.
- **Where:** `UserProfile.personalBest`, `ProfileStore`, `GoalPredictionService`, `TrainingPlanGenerator` inputs, `ProfileEditView`.
- **Done when:**
  - A PB stores its distance. A stored PB without one is migrated as the current goal's.
  - A PB for another distance is converted through VDOT, never used raw.
  - Tests cover the conversion and the migration.

### Q-05 · VO₂ max explanation is backwards, and the trend is noisy
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:**
  - The detail page says the opposite of what the engine does.
  - A 0.3 wobble between two readings counts as a falling trend and triggers an aggressive day.
- **Where:** `PaceOff/Views/VO2MaxDetailView.swift` (copy, `trendLabel`); `PushTargetEngine` (VO₂ slope).
- **Done when:**
  - The slope needs at least 3 readings over at least 14 days and a change beyond normal noise before it moves the target.
  - The detail copy describes what the engine actually does.
  - Tests cover the noise case.

### Q-06 · Notification settings don't match what fires
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:**
  - The afternoon time shows :00, but the push fires at :30.
  - There's no on/off switch, although onboarding promises one.
  - A changed time only applies after the next refresh.
- **Where:** `ProfileView` (`notificationRow`), `NotificationScheduler`, `AppGroup.Keys`.
- **Done when:**
  - The times shown are the times scheduled.
  - An on/off toggle is stored in App Group defaults and respected everywhere.
  - Changing a time or the toggle reschedules immediately.

### Q-07 · Pace Off doesn't notice a finished run
- **Status:** todo
- **Size:** M   ·   **Merge:** review
- **Problem:** The Health observer is never started, so the afternoon reminder still fires after a run until the app is opened. The background task also doesn't end cleanly when it expires.
- **Where:** `HealthKitService.startObservingVO2Max` is defined but never called; there's no workout observer; `BackgroundRefreshService` has no `expirationHandler`. The background-delivery entitlement is already in `PaceOff.entitlements`.
- **Done when:**
  - Observers on workouts and VO₂ max start at launch with background delivery.
  - When an observer fires, the app re-syncs, reschedules the pushes and reloads the widget.
  - The BG task cancels its work and completes in its expiration handler.

### Q-08 · Delete my data, and a complete sign-out
- **Status:** todo
- **Size:** M   ·   **Merge:** review
- **Problem:** SPEC promises "delete my data", but it doesn't exist. Sign-out leaves the widget data, scheduled notifications and settings behind.
- **Where:** `ProfileStore.signOut()`, `ProfileView`, `AppGroup`, `NotificationScheduler`, the widget.
- **Done when:**
  - Profile has "Delete my data". It clears every App Group key and container file, cancels notifications, reloads the widget and returns to the start.
  - Sign-out does the same.
  - SPEC § E matches.

### Q-09 · Profile repeats itself; Trends has no empty states
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:**
  - Profile shows the goal three times and the PB twice, and its prediction goes stale.
  - Trends cards show blank charts without data.
- **Where:** `PaceOff/Views/ProfileView.swift`, `PaceOff/Views/TrendsView.swift`.
- **Done when:**
  - Each fact appears once on Profile.
  - The prediction refreshes when the Health cache updates.
  - Each Trends card has an empty state.

### Q-10 · Dynamic Type, VoiceOver and Reduce Motion
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:**
  - About 30 fixed font sizes, the Today hero among them, ignore the text-size setting.
  - Some icon-only buttons have no VoiceOver label.
  - Animations outside the splash ignore Reduce Motion.
- **Where:** `grep -rn "size: [0-9]" PaceOff/Views`; icon-only `Button`s; `withAnimation` / `.symbolEffect` uses.
- **Done when:**
  - Fixed sizes become text styles or `@ScaledMetric`.
  - Every icon-only control has a label.
  - Repeating animations stop under Reduce Motion.
  - Previews at an accessibility size still lay out.

---

## Wave 3 · New features

### F-01 · Kilometres or miles
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** "km" and "/km" are hard-coded everywhere, and decimals ignore the locale.
- **Done when:**
  - A unit setting (default from the locale) drives every distance and pace through one formatter in `PaceOffShared`, with tests.
  - The engines keep working in metres.

### F-02 · Post-run feedback, and the day's target in History
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The "target hit / missed" copy exists but is never shown, and History doesn't show what the target was that day (PRD §8.2, §6.4).
- **Where:** `RunRecord.targetDistanceMeters` / `hitTarget` (never filled); `VoiceCopy`; `HistoryView`; `RunDetailView`.
- **Done when:**
  - Runs record the day's displayed target.
  - History rows and run detail show it with hit or missed.
  - One post-run notification uses the existing copy.

### F-03 · Weekly summary and streak
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** There's no weekly view of distance, runs and targets hit, and no streak beyond the Today detail line.
- **Done when:**
  - A Sunday-evening push opens a summary sheet: distance, runs, targets hit, plan adherence and the current streak.
  - The summary logic is pure and tested.

### F-04 · Plan adherence
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Past plan weeks don't show how they went.
- **Where:** `TrainingPlanReconciler`, `PlanTabView`, `TrainingPlanDetailView`.
- **Done when:**
  - Past weeks show "4/4 sessions · 92% of distance", from runs matched to plan days.
  - The matching is tested.

### F-05 · Voice choice
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The Profile "Voice: Drill Sergeant" row looks like a setting but can't be changed.
- **Done when:**
  - At least two voices (the current one plus a calmer one) live in `VoiceCopy`, chosen in Profile.
  - The choice is used by Today, the notifications and the Apple Intelligence rewrite prompt.
  - Tests cover it.

### F-06 · Haptics
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** No haptic feedback anywhere (PRD §11).
- **Done when:** `sensoryFeedback` fires on target hit, plan selected and onboarding complete.

### F-07 · Pacing intelligence in the prediction
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The per-kilometre fade analysis exists but doesn't feed the race prediction.
- **Where:** `PaceOffShared/PaceDecayAnalyser.swift`, `GoalPredictionService`.
- **Done when:**
  - A consistent late-run fade adjusts the projection, shown as one annotation on the prediction.
  - Tests cover it.

### F-08 · Hungarian localisation
- **Status:** todo
- **Size:** L   ·   **Merge:** review
- **Problem:** The app is English only. Hungarian is the first target language (PRD §15).
- **Done when:**
  - A String Catalog covers every user-facing string, including notifications and `VoiceCopy`.
  - Hungarian translations are complete.
  - Dates and numbers use the locale.

---

## Needs a decision (the loop never starts these)

### D-01 · Apple Watch: fix or hide
- **Status:** decision
- **Problem:**
  - The App Group doesn't sync between phone and watch, so a real watch always shows "—".
  - The post-run screen never appears, and cadence is always empty.
- **Options:** fix it with WatchConnectivity, the post-run screen and route recording (about a week of work), or hide the broken parts while the watch is deprioritized.

### D-02 · Is Sign in with Apple optional?
- **Status:** decision
- **Problem:** CLAUDE.md and SPEC say it's optional, but the code has no way past it, and the next screen says "No accounts".
- **Options:** add a "Continue without an account" path, or make the docs say it's required.

### D-03 · Legal text and privacy URL
- **Status:** decision
- **Problem:** The Legal screen still shows "Placeholder copy", and App Store submission needs a privacy policy URL.
- **Options:** counsel-reviewed text, plus a public Pace Off privacy page on nextcute.com, which today only opens the Wummby legal URLs without the password.

### D-04 · Live Activity and Dynamic Island
- **Status:** decision
- **Problem:** A live run on the Lock Screen (PRD §9.2) needs to know a run is in progress. That depends on D-01 and the widget's in-progress state, both on hold.

### D-05 · Buddy pairing and the V2 proposals
- **Status:** decision
- **Problem:** CloudKit, servers, paywalls and chat are out of scope for this milestone. The proposals live in `SPEC.md` § Proposals.

### D-06 · Does a run yesterday count as a skip for the target?
- **Status:** decision
- **Problem:** `PushTargetEngine` reads `daysSinceLastRun` as skipped days. So a run yesterday (gap 1) gets the one-skip +5% and the firm tone, and two missed days (gap 3) already reset to a restart. The PRD § 7 rules table, its § 7.3 worked example (two skipped days: +12%, aggressive) and the § 8.2 copy library ("Streak day 1 (yesterday ran)" vs "1 day skipped") count skips as missed days. The voice line follows that reading since R-02.
- **Options:** shift the engine by one (a run yesterday is no skip; +5% after one missed day, +12% after two, restart after three or more), which changes targets for every runner. Or keep the engine and make the PRD match it.

---

## Visual check queue

The loop works in a cloud session with no simulator: CI proves a change compiles and the tests pass, not how it looks. Every merged PR that changes UI is added here. The owner ticks it after a look on a device, in Light and Dark Mode.

- [ ] PR #20: Today's "N-day streak" label now shows before today's run, and the hero card's voice line follows the new states (streak, recovery, ran today)
- [ ] PR #17: splash → sign-in hand-off, Health-style Today (with and without data), Plan tab (with and without a plan), Profile sheet from the avatar, Trends

## Done

Newest first. The loop adds one line per merged item.

- 2026-10-31 · R-02: a run yesterday is never a skip; rest copy on recovery days; streak day number fixed via RunStreak (PR #20)
- 2026-10-30 · R-01: daily pushes are one-shot for today only; last call only after a skipped day; sign-out clears them (PR #19)
- 2026-10-26 · Redesign: icon colours in the app, Health-style Today, Plan tab, Profile behind the avatar, Dark Mode card fix (PR #17)
- 2026-10-26 · New running-track app icon (PR #16)
- 2026-10 · CI on GitHub Actions, plan-aware widget, readiness feeding the daily target, test-suite fixes (PRs #14, #15)
- 2026-10 · Background plan sync (PR #13), readiness traffic light, pace-decay analysis, Liquid Glass Today
