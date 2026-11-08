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

**Merge:** `auto` items are merged by the loop once CI is green and its own review is clean. Since 2026-11-08 every item is `auto`: the owner asked that nothing wait for their approval. A PR that changes entitlements, signing, `Info.plist` privacy strings, legal text or App Store-facing copy, or removes a feature, still merges, but says so in its title and in the run's report.

**Size:** S is a few lines to one file, M is one feature across a few files, L is several PRs. The loop splits an L item into sub-items (`R-05a`, `R-05b`…) in this file before starting it.

---

## Now · Owner's request (2026-11-08)

Requests the owner put ahead of the waves, in their order:
0. **First, every remaining fix** (owner, 2026-11-08, later the same day: "csináld meg az összes javítást loop-ban, nem kell approval"). Wave 1's R-05 and R-07b, then Wave 2's Q-02 to Q-11, come before F-10: the loop takes them in that order before anything below. The two blocked calls are Claude's to make; each item records the decision and the owner can reverse it.
1. The app in TestFlight (T-01).
2. Every card on Today opens a detail screen (F-09).
3. A morning weather check that says what to run and when (F-10).
4. Kettlebell or free-weight cross training in the plan (F-11).
5. From Claude's suggestions, picked by the owner: plan workouts on Apple Watch (F-12), sleep in readiness (F-13), best efforts and automatic PBs (F-14), easy runs that weren't easy (F-15), Siri and Control Center (F-16).

Each is split into one PR per sub-item.

### T-01 · The app in TestFlight
- **Status:** done (PR #33); uploads start once the owner's part below is done
- **Size:** S   ·   **Merge:** auto
- **Problem:** The owner wants every merged change on their phone through TestFlight, without building it by hand.
- **Where:** `.github/workflows/testflight.yml`, `ci/ExportOptions.plist`, `PaceOff/Info.plist` (export compliance), README "TestFlight".
- **Done when:**
  - Every push to `main`, and a manual run, archives the app with automatic cloud signing through an App Store Connect API key and uploads it to TestFlight. The build number is the workflow's run number.
  - Without the key the job still builds Release for a device, so a Release-only compile error shows on `main`, and skips the upload with a notice.
  - The README lists the owner's part: the App ID and App Store Connect app record, the API key with the Admin role, and the three repository secrets.
- **Owner's part:** see README "TestFlight". Until it's done, uploads are skipped.

### F-09a · HRV and Resting HR detail screens
- **Status:** done (PR #29)
- **Size:** M   ·   **Merge:** auto
- **Problem:** The HRV and Resting HR cards on Today are dead ends: no history, no baseline, nothing on how they feed readiness.
- **Where:** `TodayView` (`recoverySection`); `VO2MaxDetailView` (the pattern to follow); `HealthKitService.fetchHRVSeries` / `fetchRestingHeartRate`; `ReadinessEngine` (baselines and thresholds).
- **Done when:**
  - Tapping either card opens its detail screen, and the card shows a chevron.
  - Each screen shows the latest value against the baseline readiness uses (30-day HRV, 14-day resting HR), a chart with Week / Month / 3 Months ranges with the baseline marked, and what the number means and how Pace Off uses it.
  - The numbers come from a pure, tested function in `PaceOffShared` that agrees with `ReadinessEngine`.
  - Empty and short-history states read sensibly.

### F-09b · Last run opens the whole workout
- **Status:** done (PR #30)
- **Size:** M   ·   **Merge:** auto
- **Problem:** The Last run card has no detail. Today's run opens `RunDetailView`, but that shows only part of what Health records for a workout.
- **Where:** `TodayView` (Last run card); `RunDetailView`; `HealthKitService` (`toRunRecord`, `fetchRunLocations`, `fetchHeartRateSamples`); `RunRecord`.
- **Done when:**
  - Tapping Last run opens that run's detail (and the card shows a chevron).
  - The detail shows everything Health holds for the workout: start and end time, duration, distance, average pace and speed, heart rate (average, maximum, minimum) with a chart over time, energy, elevation gain with a profile, splits per km with pace and heart rate, cadence and steps, running dynamics (power, stride, vertical oscillation, ground contact), and weather and indoor/outdoor when recorded.
  - A field Health didn't record is left out, not shown as a dash.

### F-09c · Last 7 days opens the week
- **Status:** done (PR #31)
- **Size:** M   ·   **Merge:** auto
- **Problem:** The Last 7 days card has no detail.
- **Decision (owner left it open, 2026-11-08):** a week screen rather than a jump to the Plan tab, because it works without a plan too, where the Plan tab would only offer to pick one. With a plan active it shows the plan beside the runs and links to the Plan tab.
- **Where:** `TodayView`; `TodayViewModel.weekDistances`; `TrainingPlanReconciler`; `RootView` (switching to the Plan tab); `RunDetailView`.
- **Done when:**
  - Tapping the card opens a screen with each of the last seven days: its runs (each opens its detail) or rest, and the week's total and streak.
  - With a plan active, each day shows its plan workout and whether a run covered it, the week's total against the plan's, and a button to the Plan tab.
  - The day-by-day matching is a pure, tested function; it shares the completion rule with `TrainingPlanReconciler` (F-04 can reuse it for past weeks).

### F-09d · Readiness explains itself
- **Status:** done (PR #32)
- **Size:** S   ·   **Merge:** auto
- **Problem:** Not in the owner's list, but "every card" covers it: the Readiness card says Ready / Ease off / Rest without what it compared.
- **Where:** `TodayView` (`readinessCard`); `ReadinessEngine`; the F-09a screens.
- **Done when:** tapping it opens a screen with today's HRV and resting HR against their baselines, the thresholds that set the colour, and links to the two F-09a screens.

### F-10 · Morning weather: what to run, and when
- **Status:** todo
- **Size:** L   ·   **Merge:** see the sub-items
- **Problem:** Pace Off says how far to run, not when. The owner wants the app to check each morning's forecast in the background and send a notification saying what to run and when.
- **Approach:** WeatherKit (Apple's system framework: no third-party service, key or server of ours) and Core Location's When In Use permission at approximate accuracy. The background refresh fetches the day's hourly forecast; a pure planner picks the run's window; the morning push carries it. iOS decides when background refreshes run, so the push uses the last forecast fetched before it and leaves the weather out when that's over 12 hours old.
- **Owner's part, before F-10b:** turn on WeatherKit for the app's App ID (developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → the app → App Services → WeatherKit). Check the privacy label: the location goes only to Apple's WeatherKit, never to a server of ours, so *Data Not Collected* should still hold.
- **Defaults (the owner can change them here):**
  - Location is asked for from a Profile switch, "Weather-aware advice", off until turned on; not in onboarding.
  - The window is within the runner's waking day (from the morning push hour to 21:00) and avoids rain, temperature over 25 °C or under −5 °C feels-like, strong wind and darkness, in that order.
  - When the whole day is bad, the push names the least bad window and says so.
  - Heat over 25 °C adds "go by effort, not pace" to the plan workout's pace band.
- **Sub-items:**
  - **F-10a · Run-window planner** (M, `auto`): a pure function in `PaceOffShared` that takes an hourly forecast (temperature, feels-like, precipitation chance and amount, wind, daylight) plus the day's run (plan workout or target; none on a rest day) and returns the window and a one-line reason ("Dry and 12 °C 07:00–09:00; rain from 16:00"). Tests: rain all afternoon, a hot midday, strong wind, rain all day, a rest day.
  - **F-10b · Forecast in the morning push** (M, `auto`; it adds the WeatherKit entitlement and a location privacy string, so its PR says so): the Profile switch and location request, WeatherKit in `BackgroundRefreshService` and the foreground refresh, the forecast cached in the App Group, and `DailyPushPlanner`'s morning body leading with the window. Done when the morning push names the window whenever a fresh forecast exists, and reads exactly as today without location or forecast.

### F-11 · Cross training: kettlebell or free weights in the plan
- **Status:** todo
- **Size:** L   ·   **Merge:** see the sub-items
- **Problem:** The plan is running only, and the owner wants strength work in it, choosing kettlebell or free weights.
- **Defaults (the owner can change them here):**
  - The plan picker gets "Cross training: None / Kettlebell / Free weights", None by default; a saved plan without it decodes as None.
  - Sessions a week: Easy 1, Medium 2, Aggressive 2.
  - A session goes on a day without a run, never the day before the long run or a quality session, never two days in a row, and at least one full rest day stays in the week. When the week has no such day, it pairs with an easy run.
  - A session is about 30–40 minutes of full-body, running-specific work:
    - Kettlebell: swings, goblet squats, single-leg deadlifts, lunges, presses, carries.
    - Free weights: squats, Romanian deadlifts, split squats, step-ups, calf raises, rows, core.
  - Sessions ease off in the taper, and race week has none.
  - A strength-only day is a rest day for running: no run push, and the morning push names the session.
  - A strength workout recorded in Health that day ticks the session off.
- **Sub-items:**
  - **F-11a · Plan model and generator** (M, `auto`): `WorkoutKind.strength`, the cross-training choice on `TrainingPlanInputs` and `TrainingPlan`, placement, session templates and the taper, all in `TrainingPlanGenerator` with tests.
  - **F-11b · Showing it** (M, `auto`): the picker option, the Plan tab and plan detail rows, Today's plan line, the push text and the widget.
  - **F-11c · Done from Health** (M, `auto`): `HealthKitService` reads strength workouts (traditional and functional strength training; workouts are already readable, so no new permission) and `TrainingPlanReconciler` ticks the session off.

### F-12 · Plan workouts on Apple Watch
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** The plan's paces only live on the phone. During the run nothing tells the runner they're too fast or too slow.
- **Approach:** WorkoutKit (Apple's framework, iOS 17+) schedules custom workouts into the Watch's own Workout app, with pace alerts. No watch app of ours is involved. If this works well, D-01 can be settled by hiding our watch app.
- **Defaults (the owner can change them here):** a Plan tab switch "Send workouts to Apple Watch", off until turned on. When on, the next 7 days' run workouts are scheduled, and rescheduled whenever the plan changes or retunes. Rest days, races and (after F-11) strength sessions aren't sent. Ending the plan removes them.
- **Sub-items:**
  - **F-12a · Workout to blocks** (M): a pure function in `PaceOffShared`, with no WorkoutKit import. It turns a plan `Workout` into warm-up, work and recovery blocks and cool-down, each with its distance and pace band. Interval sessions repeat their work block; easy, long, tempo and marathon-pace runs are one work block with the pace alert. Tested.
  - **F-12b · Scheduling** (M): `WorkoutScheduler` authorization, building `CustomWorkout`s from the blocks, scheduling and removing them, and the Plan tab switch.

### F-13 · Sleep in readiness
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Readiness reads HRV and resting heart rate, not sleep, the most common reason a runner isn't ready.
- **Defaults (the owner can change them here):**
  - Last night's time asleep (Health's sleep analysis, asleep stages only) against the runner's 14-night average.
  - 15% or more short is yellow; 30% or more short is red.
  - It joins HRV and resting HR in "the worst one sets the day", and in "two signals off is red".
  - It needs 5 nights before it counts.
  - Readiness works as today without sleep data.
- **Done when:**
  - `ReadinessEngine` takes sleep, with tests.
  - `HealthKitService` reads sleep. The new read type is asked on the next authorization; the Health usage text already covers it.
  - The readiness screen shows a third signal card, and the readiness sentence names sleep when it's the cause.

### F-14 · Best efforts and automatic PBs
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** A PB is only what the runner types in. Faster efforts inside ordinary runs never improve the race prediction or the plan's VDOT.
- **Done when:**
  - A pure, tested function finds a run's fastest 1 km, 5 km, 10 km and half marathon from its route, interpolating between points.
  - The best of each over all runs read so far is kept in App Group defaults.
  - A new best gets one notification. It becomes the PB for that distance when faster; this builds on Q-04, the PB tied to its distance.
  - Profile and run detail show the bests.

### F-15 · Easy runs that weren't easy
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The most common amateur mistake, running easy days too hard, goes unnoticed.
- **Defaults (the owner can change them here):**
  - Five heart-rate zones from max HR: the highest seen in the last 90 days of runs, else 208 − 0.7 × age.
  - A plan easy or long run, or any run on a yellow or red readiness day, with more than 20% of its time above zone 2, gets a note on its run detail and in the week screen: "35% of this easy run was in zone 3 or above. Slow down to keep it easy."
- **Done when:**
  - A pure, tested function gives time in zones from heart-rate samples.
  - Run detail shows a zone bar.
  - The week screen shows the week's easy/hard balance.
  - The notes above appear.

### F-16 · Siri, Shortcuts and Control Center
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Today's target needs the app or the widget; there's no voice or one-tap way.
- **Done when:**
  - App Intents answer "What's my run today?" (the day's target and plan workout) and "How ready am I?" (readiness and its sentence) from the cached day (`WidgetCache`), without opening the app and without HealthKit in the intent.
  - App Shortcuts phrases are listed.
  - A Control Center control opens Today.
  - A day cached on an earlier date answers "Open Pace Off to get today's target", as the widget does.

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
- **Status:** done (PR #21)
- **Size:** M   ·   **Merge:** auto
- **Problem:** At night on a locked phone, HealthKit reads fail or come back empty, and the sync saves that empty result over the good cache. The next target is then a restart day, and a false "Training plan retuned" push goes out.
- **Where:** `HealthKitService.syncAll()` (saves the snapshot); `BackgroundRefreshService`; `HealthDataCache`.
- **Done when:**
  - When protected data is unavailable, or a read fails or returns nothing while the cache has data, the cache is kept, and no retune or plan notification is sent from that run.
  - The accept-or-keep rule is a pure function with tests in `HealthDataCacheTests`.

### R-04 · The daily target escapes its bounds
- **Status:** done (PR #22)
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
- **Decision (Claude, 2026-11-08, on the owner's "nem kell approval"):** option (a). A 30% cap can't hold as the plans are built: three runs a week put the long run at a third at least, and the 37 km marathon long run needs a 123 km week. So the cap fits the run count, 45% with three runs, 35% with four, 30% with five, and the long run is cut to it. What it gives up goes to the easy runs, so no week gets bigger: weekly volume is the load the plan was already prescribing. Marathon long runs now peak at 20.3 / 22.3 / 25.5 km, the half's at 15.8 / 18.0 / 21.3 km, the Easy 10K's at 12.6 km; 5K and the other 10K tiers keep theirs. The options were (b) keep the long runs and raise weekly volume or runs per week, or (c) another rule; the owner can switch to either here.
- **Where:** `PaceOffShared/TrainingPlanGenerator.swift` (week templates, long-run share).
- **Done when:**
  - The long run is at most its run count's share of the week (45% with three runs, 35% with four, 30% with five), in every tier and goal, every week but the race's.
  - The week-1 long run scales from current fitness: at most 10% past the runner's longest run of the last four weeks, never under 40% of the peak, 70% as before when nothing is known.
  - Tests assert both for every goal × tier.

### R-06 · Race-date plans jump in volume
- **Status:** done (PR #24)
- **Size:** S   ·   **Merge:** auto
- **Problem:** When a race date shortens the plan, week 2 is +43% on week 1.
- **Where:** `TrainingPlanGenerator.planWeeks(for:goalDate:)` and the volume ramp.
- **Done when:**
  - Week-over-week distance rises by at most about 10%, cutback weeks excepted, including in compressed plans.
  - Tests cover goal dates from 4 to 20 weeks out.

### R-07a · Race day in the plan
- **Status:** done (PR #25)
- **Size:** M   ·   **Merge:** auto
- **Problem:** On race day the plan prescribes a 6 km long run, with intervals two days later.
- **Where:** `TrainingPlanGenerator`; `WorkoutKind`; how the Plan tab, Today and notifications show the day.
- **Done when:**
  - A goal date inside the plan appears in it as the race.
  - The days before it taper, and the days after it are rest or easy.
  - The Plan tab, Today's plan line and the notifications name it as race day.
  - Tests cover it.

### R-07b · A race further out than the plan
- **Status:** blocked: needs the owner's call. A race further out than the goal's default plan length (16 weeks for a marathon, 12 half, 10 10K, 8 5K) falls after the plan ends: the plan starts today and finishes before the race, so the race isn't in it. Which should it be? (a) Start the plan later so it ends on race day, with the Plan tab saying when it starts. (b) Start today and add base-building weeks before the build. (c) Keep it as it is.
- **Size:** S   ·   **Merge:** auto
- **Problem:** The goal date is the race only when the plan's weeks can reach it (R-07a). A closer race ends the plan; a farther one doesn't.
- **Where:** `TrainingPlanGenerator.generate` (`raceDay`, `start`), `planWeeks(for:goalDate:today:)`; `PlanTabView` before a plan starts.
- **Done when:**
  - For any future race date, the plan has the race on its date.
  - If the plan starts later, the Plan tab says when.

### R-08 · Slow runners get paces that are too fast
- **Status:** done (PR #26)
- **Size:** S   ·   **Merge:** auto
- **Problem:** Below VDOT 25 the generator falls back to the beginner default of 38, so it prescribes paces far faster than the runner can hold.
- **Where:** `TrainingPlanGenerator` (`beginnerVDOTFallback` and the VDOT source order); `VDOTCalculator` validity range.
- **Done when:**
  - A measured VDOT below 25 is used as is, clamped only to the formula's valid range.
  - The fallback applies only when there's no measurement at all.
  - Tests cover VDOT 20, 25 and 38.

### R-09 · The widget shows stale data
- **Status:** done (PR #27)
- **Size:** S   ·   **Merge:** auto
- **Problem:** The app never asks WidgetKit to reload, so after a run the widget can stay red for up to an hour. After midnight it shows yesterday's target with a green dot.
- **Where:** nothing calls `WidgetCenter.shared.reloadAllTimelines()`; `TodayViewModel.refresh()`, `BackgroundRefreshService`, `PaceOffWidget.swift` (`PaceOffProvider`).
- **Done when:**
  - The app reloads timelines after writing the target or plan status.
  - The widget timeline has an entry at the next midnight.
  - A target computed on an earlier day renders as "Open Pace Off" with a neutral dot, not as today's, and its voice line ("Run logged. Recover and go again tomorrow.") isn't shown the next day.

---

## Wave 2 · Quality

### Q-01 · Notification "Not now" asks for permission anyway
- **Status:** done (PR #28)
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
  - Turning the toggle on when iOS was never asked ("Not now" in onboarding, Q-01) requests permission then.

### Q-07 · Pace Off doesn't notice a finished run
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The Health observer is never started, so the afternoon reminder still fires after a run until the app is opened. The background task also doesn't end cleanly when it expires.
- **Where:** `HealthKitService.startObservingVO2Max` is defined but never called; there's no workout observer; `BackgroundRefreshService` has no `expirationHandler`. The background-delivery entitlement is already in `PaceOff.entitlements`.
- **Done when:**
  - Observers on workouts and VO₂ max start at launch with background delivery.
  - When an observer fires, the app re-syncs, reschedules the pushes and reloads the widget.
  - The BG task cancels its work and completes in its expiration handler.

### Q-08 · Delete my data, and a complete sign-out
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
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

### Q-11 · The check-in card shows another day's "yesterday"
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** The cached snapshot stores yesterday's HRV and average heart rate as plain numbers. When Today renders a cache synced on an earlier day (cold launch, or a sync that kept the cache), the morning check-in card shows those values as yesterday's, though they belong to the day before the sync.
- **Where:** `HealthDataSnapshot.yesterdayHRV` / `yesterdayAvgHeartRate` (`PaceOffShared/HealthDataCache.swift`); `TodayViewModel.applySnapshot`; the check-in card.
- **Done when:**
  - Day-relative values from a snapshot synced on an earlier calendar day aren't shown as yesterday's. Either hide them, or label them with their day.
  - A pure check with tests decides it.

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
- **Size:** L   ·   **Merge:** auto
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

### D-07 · Rebuild saved plans when the generator changes?
- **Status:** decision
- **Problem:** An active plan is saved in full in `training-plan.json`. The background retune only re-paces it and never rebuilds distances. Generator fixes (R-06's 10% ramp, and later R-05, R-07, R-08) therefore reach a runner only when they choose a plan again. A race-date plan picked before R-06 keeps its +43% week.
- **Options:**
  - Rebuild the remaining weeks of an active plan built by an older generator, keeping completed weeks as they were. This needs a generator version stored on the plan.
  - Offer the rebuild with a prompt on the Plan tab.
  - Leave saved plans alone.

---

## Visual check queue

The loop works in a cloud session with no simulator: CI proves a change compiles and the tests pass, not how it looks. Every merged PR that changes UI is added here. The owner ticks it after a look on a device, in Light and Dark Mode.

- [ ] PR #32: Today's Readiness card (chevron) and its screen: the verdict, the two signal cards with their grades (each opening its HRV / Resting HR screen), the rules card, and the not-enough-history state
- [ ] PR #31: Today's Last 7 days card (chevron) and the week screen, with and without a plan: the bars and dashed plan lines, the plan card and its "Open training plan" button switching tabs, the day cards and their marks, a run opening its detail
- [ ] PR #30: Today's Last run card (chevron) and the run detail: start–end time, the summary tiles, the heart rate chart, the elevation profile, the splits table; a treadmill run shows "Indoor" and no elevation
- [ ] PR #29: Today's HRV and Resting HR cards (chevron) and their detail screens: the summary line's colour, the Week / Month / 3 Months picker, the dashed baseline, the "baseline appears after N more days" line with short history, and the empty state
- [ ] PR #28: onboarding's notifications step: "Not now" goes straight to the last step with no system prompt (and hides while the prompt is up); "Allow Notifications" still shows it; the new footnote; Profile → Notifications → "Allow notifications" shows the prompt after a "Not now"
- [ ] PR #27: the widget (all four families) right after a run logged in the app, and after midnight before opening the app: "—", "Open Pace Off" and a grey dot; the stale entry in the systemSmall preview
- [ ] PR #25: the Plan tab on race day (hero "Race day", the race row marked in the week), the plan detail week with the race, and Today's plan line "… plan · Race day"; a new race plan's week 1 can show a few days already past
- [ ] PR #20: Today's "N-day streak" label now shows before today's run, and the hero card's voice line follows the new states (streak, recovery, ran today)
- [ ] PR #17: splash → sign-in hand-off, Health-style Today (with and without data), Plan tab (with and without a plan), Profile sheet from the avatar, Trends

## Done

Newest first. The loop adds one line per merged item.

- 2026-11-08 · T-01: every push to main builds Release for a device and, once the App Store Connect key's secrets exist, uploads to TestFlight; every item is now auto-merged (PR #33)
- 2026-11-08 · F-09d: Readiness opens a screen with each signal against its baseline, how the two combine and what each colour does to the target; every Today card now has a detail (PR #32)
- 2026-11-08 · F-09c: Last 7 days opens a week screen: each day's runs and, with a plan, its workout marked done, to do, missed or rest, with a way to the Plan tab (PR #31)
- 2026-11-08 · F-09b: Last run opens the run's detail, which now shows every figure Health recorded, heart rate over time, the elevation profile and a splits table (PR #30)
- 2026-11-08 · F-09a: the HRV and Resting HR cards open detail screens with their baseline, a Week / Month / 3 Months chart and how readiness grades them (PR #29)
- 2026-11-08 · Q-01: "Not now" on onboarding's notifications step moves on without asking iOS for permission (PR #28)
- 2026-11-07 · R-09: the app reloads the widget after each refresh; its timeline turns at noon and midnight, and a day cached earlier shows "Open Pace Off", never as today's (PR #27)
- 2026-11-06 · R-08: a slow runner's measured VO₂ max or PB is used (below VDOT 20 it's raised to 20); junk readings (outside 10–90) are ignored; the beginner default only when there's no usable measurement (PR #26)
- 2026-11-05 · R-07a: a reachable race is the plan's last day, counted back from it, with a rest day and no hard sessions before it; R-07b blocked (PR #25)
- 2026-11-04 · R-06: weekly distance rises at most 10% a week; plans shortened by a race date peak lower instead of jumping (PR #24)
- 2026-11-03 · R-04: restart days capped by the 1.4× ceiling; the shown whole km never exceeds the day's cap (PR #22)
- 2026-11-02 · R-03: a locked, failed or empty Health read keeps the cache; only a fresh read retunes the plan (PR #21)
- 2026-10-31 · R-02: a run yesterday is never a skip; rest copy on recovery days; streak day number fixed via RunStreak (PR #20)
- 2026-10-30 · R-01: daily pushes are one-shot for today only; last call only after a skipped day; sign-out clears them (PR #19)
- 2026-10-26 · Redesign: icon colours in the app, Health-style Today, Plan tab, Profile behind the avatar, Dark Mode card fix (PR #17)
- 2026-10-26 · New running-track app icon (PR #16)
- 2026-10 · CI on GitHub Actions, plan-aware widget, readiness feeding the daily target, test-suite fixes (PRs #14, #15)
- 2026-10 · Background plan sync (PR #13), readiness traffic light, pace-decay analysis, Liquid Glass Today
