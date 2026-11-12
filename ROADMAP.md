# Pace Off — Roadmap

The backlog the roadmap loop works through, in priority order. `LOOP.md` is the procedure; this file is the queue. Edit it freely: reorder items, add new ones, set a status. The loop reads it fresh on every run, and the topmost workable item always wins.

The items come from two sources: the full code review of 2026-10-18, re-checked against the source on 2026-10-29, and, from Step 0 on, the competitor research of 2026-11-12 (`docs/research-2026-11.md`, in Hungarian; `ARCHITECTURE.md` has the plan that came out of it). Line numbers drift: treat **Where** as a starting point and confirm the problem in the code before changing anything.

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

## Direction (2026-11-12)

The owner's goal: Pace Off is the runner's alpha and omega. What that can mean without a server, from the research: **the number-one coach for runners with an iPhone and an Apple Watch.** Pace Off owns the start of the day (what to run, and why) and the end (how it went, and what changes because of it). Recording the run stays with Apple's Workout app until the owner decides otherwise (D-10).

What the research found, in the order it shapes this file:

- **Injury is why runners stop** (48% of beginners who quit). The clearest load signal is one run much longer than anything in the last 30 days, not the week's total (BJSM 2025, 5,205 runners). No large app caps the single run yet. → R-11
- **Pace Off gives two prescriptions on a plan day, and its plan adapts paces only.** Runna, the benchmark coach at US$119.99 a year, moves and skips sessions and re-plans, but has no pause and is criticised for paces that are too fast. → R-10, F-17, F-21
- **Apple leaves the prescription open.** Its Readiness score labels the day and runs only on the newest watches; Workout Buddy has no plan and no developer API. WorkoutKit puts our plan into Apple's Workout app. → F-12
- **The on-device model can phrase, not decide.** It runs from iPhone 15 Pro and, as far as the evidence shows, doesn't write Hungarian. Facts and templates are the product; the model is an optional last layer. → R-12, F-19
- **No backend.** Nothing through Step 3 needs one. The limits, and the four cases that would need one, are in `ARCHITECTURE.md`.
- **What is free at launch stays free.** Every paywall added later drew a backlash: Strava's yearly recap, Runna's beginner plans, Garmin Connect+. → D-11

The queue follows four steps. The file's order is the loop's order.

| Step | Aim | Items, in order |
|---|---|---|
| 0 | Safe and consistent advice | R-12, R-10, R-11, Q-13 |
| 1 | One coach: on the wrist, adapting, explaining itself, in the runner's units and language | F-12, F-14, F-17, F-13, F-18, F-20, F-15, F-16, F-01, F-08, F-19, F-21 |
| 2 | Breadth: more runners, and more of their running | F-10, F-22, F-05, F-23, F-03, F-04, F-31, F-30, F-25, F-07, F-24, F-32, F-27, F-26, F-28, F-29, F-33, F-34, F-06 |
| 3 | Completeness: race day, and the decisions that open new ground | F-35, then "Needs a decision" |

F-01 (miles) and F-08 (languages) come before the coach's note on purpose: the note is mostly copy, and copy written after them is born in the runner's units and language.

## Owner's part

What only the owner can do. None of it stops the loop's next item; each holds something back.

- [ ] **TestFlight** (T-01): the App ID, the App Store Connect app record, the API key and the three repository secrets (README "TestFlight"). Until it's done, merged changes don't reach a device through TestFlight.
- [ ] **WeatherKit** for the App ID (F-10). It unblocks F-10b and F-22.
- [ ] **A look on a device.** The Visual check queue below holds every UI change since PR #17, none ticked.
- [ ] **Three short checks on a real iPhone and Apple Watch** that the research couldn't settle:
  - after F-12b: how many workouts `WorkoutScheduler` accepts, and whether Workout Buddy speaks during one of ours;
  - any time: whether the on-device model lists Hungarian (`SystemLanguageModel.default.supportedLanguages`).
- [ ] **App Store Connect:** Health & Fitness apps distributed in the EEA, the UK or the US now declare whether they are a regulated medical device. Pace Off gives training advice, not diagnosis; the declaration is the owner's to make, before the first submission.
- [ ] **Decisions**, under "Needs a decision". D-01 and D-02 come first: they gate the release.

---

## Step 0 · Safe and consistent advice

These tell the runner the wrong thing, or prescribe a load the evidence warns against. They go before any feature.

### R-12 · The Apple Intelligence rewrite can change the numbers
- **Status:** done (PR #53)
- **Size:** S   ·   **Merge:** auto
- **Problem:** Today's voice line and the push text are rewritten by the on-device model, and the result is accepted on its length alone. A rewrite that turns "6 km" into "8 km", or adds a number, would go out as the day's advice. The code's comment says such lines are rejected; nothing does it. The rewrite also runs in the background refresh, where the system rate-limits the model, and it runs twice per refresh.
- **Where:** `AppleIntelligenceCopy.sanitize` (length only); its call sites in `TodayViewModel.refresh` and `BackgroundRefreshService`.
- **Done when:**
  - A pure, tested check in `PaceOffShared` (`NarrationCheck`) accepts a rewrite only when it carries exactly the numbers of the original, each as often, in any order, and stays within the length cap. A rewrite that fails falls back to the canned line.
  - The background refresh uses the canned lines and never calls the model.
  - The foreground refresh reuses an accepted rewrite while the canned line it came from is unchanged.
  - Tests: a changed number, an added one, a dropped one, a number written as a word ("six"), decimals, and a pace band ("5:25–5:45/km").

### R-10 · A plan day has two prescriptions
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** With a plan active, Today's big number is the daily-target engine's distance and the plan's workout is a label under it. "Target hit" is judged against the engine's number. A push can name two distances: "Today's plan: 8.0 km · 5:25–5:45/km. Yesterday: done. Today: 6 km." On a plan rest day the push says rest while Today still shows a target. Once F-12 sends the plan's workout to the watch, the wrist and the phone would disagree as well.
- **Decision (Claude, 2026-11-12; the owner can reverse it):** on a day with a plan run, the plan's workout is the day's prescription, and readiness changes that workout instead of a second number. A plan rest day shows as rest. Without a plan, or before a plan's first week, the daily target works as today.
- **Defaults (the owner can change them here):**
  - Green, or no readiness yet: the plan's workout as written.
  - Yellow: the plan's distance at easy pace. A quality session loses its fast part.
  - Red: an easy run of at most 60% of the plan's distance, the factor a red day already uses.
  - Race day: readiness never changes the race.
  - "Target hit" is the plan's completion rule, 85% of the day's prescribed distance.
- **Where:** `TodayView` (the hero's `displayedDistanceKm`, the "Target hit" badge), `TodayViewModel.refresh`, `VoiceState` / `VoiceCopy`, `DailyPushPlanner` (the body joins the plan line and the voice line), `WidgetCache`, `PaceOffWidget`.
- **Sub-items:**
  - **R-10a · The day's prescription** (M): a pure function in `PaceOffShared` (`DayPrescription`) takes the plan day's status, the readiness verdict and the engine's target, and returns the one prescription for today: its kind (run, rest, strength, race), distance, pace band or "easy", and what changed it. Tests cover each default above, no plan, a plan that hasn't started, a rest day and a strength-only day.
  - **R-10b · Every surface reads it** (M): Today's hero, its badge and its voice line, the pushes, the widget and its cache. Done when no screen or push shows the engine's number on a plan-run day, a push never names two distances, and a plan rest day shows as rest.

### R-11 · One run can jump far past anything recent
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The daily target is capped at 1.4× the median run of the last 14 days, so it can ask for a run well past the runner's longest recent one: a runner whose runs are all about 5 km can be sent 6.4 km, a 29% jump (the PRD's own example, pinned in `PushTargetEngineTests`). A plan workout isn't checked against what was actually run: after three missed long runs, the fourth is still the plan's number. The largest study of running load (BJSM 2025; 5,205 runners, 588,071 runs) found the overuse-injury rate 64% higher after a run more than 10% longer than the longest of the previous 30 days, and 128% higher when it more than doubled. Week-to-week change showed no link.
- **Defaults (the owner can change them here):**
  - No prescribed run is longer than 110% of the longest run of the previous 30 days.
  - It applies to the daily target and to today's plan workout (through R-10's prescription). The plan keeps its own numbers until F-21 rebuilds it from what was run.
  - With no run in the last 30 days, the restart rules apply as today.
  - Race day is never cut.
  - A capped day says so in one line: "Kept to 11 km: 10% past your longest run of the last 30 days."
  - The copy never promises fewer injuries. The study is observational, and most injuries in it followed runs with no jump.
- **Where:** `PushTargetEngine` (the caps, `RunTarget`), `DayPrescription` (R-10a), `TrainingPlanReconciler.todayStatus`.
- **Done when:**
  - A pure, tested function gives the day's single-run cap from the runs of the previous 30 days.
  - The daily target never exceeds it, its reasoning names the cap when it applied, and the whole km shown stays within it (R-04's rule).
  - Today's plan workout, when over the cap, is shown and pushed at the cap with the line above, and the plan's own number shows beside it.
  - Tests: the runner whose runs are all 5 km; a long run after three missed weeks; a runner back after 31 days; race day.

### Q-13 · The iPhone app declares things it doesn't do
- **Status:** todo
- **Size:** S   ·   **Merge:** auto (the PR's title says it changes `Info.plist` privacy strings and background modes)
- **Problem:** `PaceOff/Info.plist` still carries an earlier "record on iPhone" plan: a Health write description ("saves running workouts you start in the app"), a motion description and the `remote-notification` background mode. `HealthKitService.requestAuthorization` asks for write access too. No iPhone code writes a workout, reads motion or receives a remote push. The Health permission sheet promises a feature that isn't there, and App Review asks about access that is declared and unused.
- **Where:** `PaceOff/Info.plist`, `HealthKitService.requestAuthorization` (`writeTypes`), `PaceOff.entitlements`.
- **Done when:**
  - The iPhone app asks Health for read access only, and the three leftovers are gone.
  - The watch target, which does write workouts, keeps what it needs.
  - README and SPEC say the same. If D-10 (recording on iPhone) is approved, they come back with it.

---

## Step 1 · One coach: on the wrist, adapting, explaining itself

### F-12 · Plan workouts on Apple Watch
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** The plan's paces only live on the phone. During the run nothing tells the runner they're too fast or too slow. Sending the workout to the watch is the baseline for plan apps on Apple Watch: Runna and TrainingPeaks do it, and Run With Hal is marked down for not doing it.
- **Approach:** WorkoutKit (Apple's framework, iOS 17+) schedules custom workouts into the Watch's own Workout app, with pace alerts, under Pace Off's name and icon. No watch app of ours is involved. If this works well, D-01 can be settled by hiding our watch app. Workout Buddy can't be driven by an app; whether it speaks during a scheduled workout is one of the owner's checks.
- **Defaults (the owner can change them here):**
  - A Plan tab switch "Send workouts to Apple Watch", off until turned on.
  - When on, the next 7 days' run workouts are scheduled, and rescheduled whenever the plan changes or retunes. The watch shows workouts from 7 days back to 7 days ahead.
  - Today's entry follows the day's prescription (R-10, R-11) when the phone refreshes; later days are the plan's.
  - Rest days, races and strength sessions aren't sent. Ending the plan removes them.
  - The number of workouts the system accepts isn't documented (15 in Apple's 2023 talk, 50 in developer reports from 2024): read `WorkoutScheduler.maxAllowedScheduledWorkoutCount` at run time and never schedule more.
- **Sub-items:**
  - **F-12a · Workout to blocks** (M): a pure function in `PaceOffShared`, with no WorkoutKit import. It turns a plan `Workout` into warm-up, work and recovery blocks and cool-down, each with its distance and pace band. Interval sessions repeat their work block; easy, long, tempo and marathon-pace runs are one work block with the pace alert. Tested.
  - **F-12b · Scheduling** (M): `WorkoutScheduler` authorization, building `CustomWorkout`s from the blocks, scheduling and removing them, and the Plan tab switch. The cloud can't prove this one: its Visual check line asks the owner to run one scheduled workout on a real watch.

### F-14 · Best efforts and automatic PBs
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** A PB is only what the runner types in. Faster efforts inside ordinary runs never improve the race prediction or the plan's VDOT.
- **Done when:**
  - A pure, tested function finds a run's fastest 1 km, 5 km, 10 km and half marathon from its route, interpolating between points.
  - The best of each over all runs read so far is kept in App Group defaults.
  - A new best gets one notification. It becomes the PB for that distance when faster; this builds on Q-04, the PB tied to its distance.
  - Profile and run detail show the bests.

### F-17 · Paces from what the runner actually ran
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Plan paces and the retune take Health's VO₂ max first, and a PB only when there is none (`resolveVDOT`). In two lab studies the Apple Watch estimate read about 6 ml/kg/min low on average (13% error; only 14% of people landed in the right fitness band), and a few units of VDOT move every pace by many seconds per km. A recent hard run says more than the estimate, and F-14 finds those. Today a new best changes nothing in the plan while a VO₂ max reading exists.
- **Defaults (the owner can change them here):**
  - The plan's VDOT is the higher of two: the best VDOT among the 5 km, 10 km and half-marathon best efforts of the last 90 days, and Health's latest VO₂ max. A runner who raced lately gets paces from the race; one who only jogs isn't slowed down to the jog.
  - Without either: the typed PB, then the beginner default, as today.
  - The 1 km best effort never sets paces: a short effort overstates endurance.
  - The plan's detail says where its paces come from: "Paces from your 10 km on 3 Nov (48:12)" or "Paces from your VO₂ max in Health (46.1)".
- **Where:** `TrainingPlanGenerator.resolveVDOT`, `TrainingPlanInputs`, `BackgroundRefreshService` (the retune resolves VDOT the same way), `GoalPredictionService`, F-14's store.
- **Done when:**
  - The rule is one pure function, used by the picker, the retune and the prediction.
  - The plan records its pace source and the detail screen shows it.
  - Tests: a recent race above the estimate, only easy runs below it, neither, and an effort older than 90 days.

### F-13 · Sleep in readiness
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Readiness reads HRV and resting heart rate, not sleep, the most common reason a runner isn't ready. In a cohort of 339 runners, poorer sleep went with a 36% higher injury risk.
- **Defaults (the owner can change them here):**
  - Last night's time asleep (Health's sleep analysis, asleep stages only) against the runner's 14-night average.
  - Only the time asleep counts, never its split into stages: against a sleep lab the Apple Watch under-read deep sleep by 43 minutes.
  - 15% or more short is yellow; 30% or more short is red.
  - It joins HRV and resting HR in "the worst one sets the day", and in "two signals off is red".
  - It needs 5 nights before it counts.
  - Readiness works as today without sleep data.
- **Done when:**
  - `ReadinessEngine` takes sleep, with tests.
  - `HealthKitService` reads sleep. The new read type is asked on the next authorization; the Health usage text already covers it.
  - The readiness screen shows a third signal card, and the readiness sentence names sleep when it's the cause.

### F-18 · A memory: what was prescribed, and what was run
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Pace Off keeps nothing about a day once it's over. A run gets a new `id` on every Health read, `RunRecord.targetDistanceMeters` and `hitTarget` are never filled, and the prescription shown on a past day can't be found again. The run review, plan adherence for past weeks, shoes, the recap and an adaptive plan all need it.
- **Where:** `RunRecord` (identity), `HealthKitService.toRunRecord` (`workout.uuid`), `AppGroup` (`containerFiles`), `TodayViewModel.refresh` and `BackgroundRefreshService` (where the day is computed), `HealthDataCache` (the actor-and-JSON pattern to follow).
- **Done when:**
  - A run's `id` is its Health workout UUID, the same on every read.
  - `RunLedger`, an actor in `PaceOffShared` writing `run-ledger.json` in the App Group container, records for each day the prescription as it was shown (kind, distance, pace band, what changed it) and for each run the day it belongs to. A fresh sync writes today's row, a later refresh the same day replaces it, and past days are never rewritten.
  - The file is versioned, decodes when fields are missing, starts empty when unreadable, and joins `AppGroup.containerFiles`, so Delete My Data and sign-out erase it.
  - Nothing in it leaves the device (`ARCHITECTURE.md`, the iCloud rule).
  - Tests: write and read, the same-day replacement, a past day kept, a corrupt file.

### F-20 · The runner's own word in readiness
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Readiness hears the watch, never the runner. Sore legs, a cold or a rough night with a child never reach HealthKit. Self-reported measures follow training load more sensitively and consistently than objective ones (a review of 56 studies), and the one trial in which HRV-guided training beat a fixed plan for recreational runners (10 km time down 6.2% against 2.9%) combined HRV with how recovered the runners felt.
- **Defaults (the owner can change them here):**
  - One optional question on Today each morning, one tap: Fresh, Normal, Tired, Sore, Unwell. No reminder, no streak, nothing happens when it's skipped.
  - Tired or Sore counts as one signal off: yellow alone, red with another signal off.
  - Unwell is red, and the day's advice is rest. Once F-21c exists, Today offers to pause the plan.
  - Fresh never overrides a yellow or red from the watch.
  - The answer is stored with the day in the ledger (F-18) and stays on the device.
- **Done when:**
  - `ReadinessEngine` takes the answer, with tests.
  - Today asks once a day, and the answer can be changed.
  - The readiness screen shows it as its own signal card.

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
- **Problem:** Today's prescription needs the app or the widget; there's no voice or one-tap way. App Intents have no fitness schema, and custom actions for Siri's AI reach the App Store only in spring 2027 (not in the EU), but the entities and actions built now are what it will use.
- **Done when:**
  - App Intents answer "What's my run today?" (the day's prescription, R-10) and "How ready am I?" (readiness and its sentence) from the cached day (`WidgetCache`), without opening the app and without HealthKit in the intent.
  - App Shortcuts phrases are listed.
  - A Control Center control opens Today.
  - A day cached on an earlier date answers "Open Pace Off to get today's target", as the widget does.

### F-01 · Kilometres or miles
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** "km" and "/km" are hard-coded everywhere, and decimals ignore the locale. A runner in the US or the UK can't use the app as it is.
- **Sub-items:**
  - **F-01a · One formatter** (M): a unit setting (default from the locale) and one formatter in `PaceOffShared` for distances, paces and speeds, with tests. The engines keep working in metres. Whole-unit rounding rules (R-04's "never above the cap") hold in miles too.
  - **F-01b · Every screen, push and widget through it** (M): no "km" literal is left outside the formatter; plan notes, session notes and the voice lines included. Best efforts add the mile.

### F-08 · Languages: Hungarian first
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** The app is English only. Hungarian is the first target language. The on-device model doesn't write Hungarian as far as the evidence shows, so for a Hungarian runner the canned lines and the templates are the whole product.
- **Sub-items:**
  - **F-08a · A String Catalog and the rule** (L; the loop splits it by area: views, shared copy, notifications): every user-facing string goes through the catalog, including notifications, `VoiceCopy`, plan and session notes. Keys are the English text, so the unit tests keep asserting English. Dates and numbers use the locale. `CLAUDE.md` gains the rule that new copy ships in every supported language.
  - **F-08b · Hungarian** (M): complete translations, in the informal register a running friend would use. The Apple Intelligence rewrite is skipped when the model doesn't support the app's language (ask `supportsLocale`, don't keep a list).

### F-19 · The coach's note: how the run went, and why today's is what it is
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** Pace Off never says how a run went against what it was for. The "target hit / missed" copy exists and nothing fills it (`RunRecord.hitTarget`, the History icon); the pacing headline on run detail doesn't know the workout's intent; Today's reasoning doesn't say which signal changed the day. Runna gives a pace verdict after every paced run and Stryd a written recap. Strava and Garmin sell AI summaries that reviewers call thin, because they don't know what the run was for. Pace Off knows: it wrote the prescription.
- **Approach** (`ARCHITECTURE.md`, "Apple Intelligence"): a pure function builds the facts and the verdict. A template turns them into two or three sentences and one tip, for every runner in every language. On phones with Apple Intelligence the on-device model may rephrase them, checked against the facts, never in the background. This is the app's first real Apple Intelligence feature, and it replaces F-02.
- **Sub-items:**
  - **F-19a · Run review** (M): `RunReviewFacts` from the run and the day's prescription in the ledger (F-18): distance against prescribed, average pace against the band, the fade from `PaceDecayAnalyser`, the share of time above zone 2 (F-15), whether the single-run cap applied. A verdict: on plan, too fast, too slow, cut short, went long, easy run too hard, unplanned. Template text for each. Run detail leads with the note, History rows show hit or missed, and one notification follows a run. Tests for each verdict.
  - **F-19b · Why this today** (M): `DayReasoningFacts` from `DayPrescription`: the signals that moved today's prescription, strongest first (readiness and which signal, yesterday's run, the plan's week, the single-run cap, the forecast once F-10b exists), each with its number. Today's hero opens it, and the morning push leads with the strongest reason. Tests.
  - **F-19c · In Apple Intelligence's words** (M): the on-device model (Foundation Models, guided generation) rephrases a note. Done when:
    - it runs only in the foreground, after a prewarm, never in the background refresh;
    - a rewrite shows only when `NarrationCheck` (R-12) passes and the verdict is unchanged, else the template stays;
    - nothing is asked when the model is unavailable or doesn't support the app's language;
    - an accepted rewrite is cached with its note in the ledger;
    - the note is marked "Written by Apple Intelligence", Profile has a switch for it, and "Report this note" puts the template back;
    - its Visual check line asks the owner to read ten notes on a real phone.

### F-21 · A plan that adapts
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** After a plan is chosen only its paces change. A skipped run, a week of flu, a holiday or a second race changes nothing in the weeks ahead, and the only action in Plan Settings is "End this plan". Runna lets a runner drag a session within its week, skip it with a re-plan, switch to a holiday mode and add a tune-up race; it has no pause, and a session can't leave its week. Stryd pauses and resumes with a preview of what changes. A real pause and moves across weeks are where the benchmark can be passed.
- **Approach:** one primitive, "rebuild from here". The generator makes the remaining weeks again from today, for the same race day (or the plan's original last day), tier, long-run day and kit, from the runner's current VDOT and what the ledger says was run. Finished weeks stay as they were. Every change is shown before it applies and can be undone.
- **Defaults (the owner can change them here):**
  - A missed long run or quality session is never made up by adding it elsewhere.
  - After 7 days or more without a run, the first week back is at most 70% of the last week that was run, easy runs only.
  - With a race date, a pause shortens the build and the race stays. Without one, the plan's last day moves by the length of the pause.
- **Sub-items:**
  - **F-21a · Rebuild from here** (M): the generator primitive, with tests (the same race day; the first rebuilt week starts from the longest run of the last 30 days under R-11's rule; no week over the 10% ramp; the taper intact). A preview sheet says what changes, with accept and undo. Plan Settings gains "Runs per week", "Long run day" and "Cross training" as changes that rebuild. This is also what D-07 needs, if the owner chooses to offer rebuilds after generator fixes.
  - **F-21b · Skip or move a session** (M): from the Plan tab, a session can be skipped, or moved to another day of this week or the next. A pure function checks the week (no hard session the day before the long run, no two hard days in a row, one full rest day stays) and warns instead of forbidding. A missed long run rebuilds the next week from what was run.
  - **F-21c · Pause and resume** (M): "Pause the plan" with a reason (ill, injured, away). While paused there are no plan pushes and Today shows the daily target, or rest when the runner said Unwell (F-20). Resuming rebuilds from here, and the shortfall line says what the pause cost.
  - **F-21d · A tune-up race** (M): a second race on a date inside the plan. The day before is rest, the two days before carry no hard session, the race replaces that week's long run or quality session, and the two days after are easy or rest.

---

## Step 2 · Breadth: more runners, and more of their running

### F-10 · Morning weather: what to run, and when
- **Status:** blocked: F-10a done (PR #48); F-10b needs the owner to turn on WeatherKit for the App ID first (Owner's part below). Delete this reason once it's on, and the loop builds F-10b
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
  - **F-10a · Run-window planner** (M, `auto`), **done (PR #48)**: a pure function in `PaceOffShared` that takes an hourly forecast (temperature, feels-like, precipitation chance and amount, wind, daylight) plus the day's run (plan workout or target; none on a rest day) and returns the window and a one-line reason ("Dry and 12 °C 07:00–09:00; rain from 16:00"). Tests: rain all afternoon, a hot midday, strong wind, rain all day, a rest day.
  - **F-10b · Forecast in the morning push** (M, `auto`; it adds the WeatherKit entitlement and a location privacy string, so its PR says so): the Profile switch and location request, WeatherKit in `BackgroundRefreshService` and the foreground refresh, the forecast cached in the App Group, and `DailyPushPlanner`'s morning body leading with the window. Done when the morning push names the window whenever a fresh forecast exists, and reads exactly as today without location or forecast.

### F-22 · Heat changes the pace, not only the hour
- **Status:** blocked: needs F-10b (the forecast). Delete this reason once F-10b is merged
- **Size:** M   ·   **Merge:** auto
- **Problem:** F-10's only word on heat is "go by effort, not pace" above 25 °C. Runna shipped Adapt for Heat in July 2026: pace targets change with the feels-like temperature, the session's length and its type. Running performance is best at 7.5–15 °C WBGT (about 10–17.5 °C in the air) and falls 0.3–0.4% for each degree outside it, more for slower runners, so a 25 °C threshold comes late.
- **Defaults (the owner can change them here):**
  - Above 15 °C feels-like in the run's window, each pace band slows by 0.4% per degree, up to 8%. Above 25 °C "go by effort, not pace" stays as well.
  - The prescription says so: "Paces eased 4% for 26 °C."
  - No change below 15 °C, and never a faster band.
  - When the window is in the dark, the push adds one line suggesting a Check In in Messages. Apple's Check In tells a contact when the runner is back; it needs no server and no access of ours.
- **Done when:** the rule is a pure, tested function over the forecast and the workout; `DayPrescription` applies it and names it in the reasoning (F-19b); the workout sent to the watch (F-12) carries the eased band.

### F-05 · Voice choice
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The Profile "Voice: Drill Sergeant" row looks like a setting but can't be changed, and every state has one fixed line. Beginners drop out partly because they feel they've failed, and in the one small study that tested it, feedback framed around losing did worse than feedback framed around gaining.
- **Done when:**
  - At least two voices live in `VoiceCopy`: the drill sergeant and an encouraging one, chosen in Profile.
  - The encouraging voice is the default for the beginner plans (F-23). Nobody's current voice changes.
  - The choice is used by Today, the notifications, the coach's note templates (F-19) and the Apple Intelligence prompt.
  - Tests cover it.

### F-23 · A first plan, and a way back
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** The shortest plan assumes a runner who can already run 5 km: below that the plans start too high (week 1's long run is never under 40% of the plan's peak). Beginners quit mostly through injury, and only 27% finished a Couch-to-5K cohort, blaming injury, the feeling of failure and a progression that wouldn't bend; 64% of that cohort had run before. Runna put its beginner and return plans behind its subscription in June 2026, so a free, forgiving way in has few strong rivals on iPhone.
- **Defaults (the owner can change them here):**
  - Two more goals in the plan picker: **Start running** (to 30 minutes without a walk break) and **Back to running** (after a month or more away).
  - Three days a week. Sessions are by time, not distance: run and walk steps that lengthen week by week. No pace band: "a pace you can talk at".
  - Start running takes 9 weeks from 1-minute runs. Back to running starts from the longest run in Health in the last 90 days (from 1-minute runs when there is none) and takes as many weeks as that leaves.
  - Any week can be repeated, and the plan moves on when the week's three sessions are done, not when the calendar says so. A missed week is never called a failure.
  - Finishing offers the 5K plan, starting from what was just run.
- **Sub-items:**
  - **F-23a · Timed run–walk sessions** (M): the plan model and generator: a workout made of timed run and walk steps, the two progressions, repeat and advance, with tests.
  - **F-23b · Showing and sending them** (M): the picker, the Plan tab, Today, the pushes, the widget, and WorkoutKit steps by time (F-12).

### F-03 · The week, the month and the year in review
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** There's no weekly view of distance, runs and sessions done, and nothing for a month or a year. Strava made its yearly recap subscriber-only in December 2025 and Garmin tied its own to Connect+; both drew a backlash. The streak counts consecutive running days, which rewards skipping rest: runners interviewed about their streaks had run injured to keep the count.
- **Defaults (the owner can change them here):**
  - A streak day is a day the prescription was met: the run done, or the rest taken. Missing a prescribed run ends it; an extra run on a rest day doesn't.
  - A broken streak is never mentioned in a push.
- **Done when:**
  - A Sunday-evening push opens a summary sheet: distance, runs, sessions done of those planned, the week's run verdicts (F-19a) and the streak.
  - Month and year recaps are computed on the phone from Health and the ledger, and are free.
  - The summary and streak logic is pure and tested.

### F-04 · Plan adherence
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Past plan weeks don't show how they went.
- **Where:** `TrainingPlanReconciler`, `WeekReview`, the ledger (F-18), `PlanTabView`, `TrainingPlanDetailView`.
- **Done when:**
  - Past weeks show "4/4 sessions · 92% of distance", from runs matched to plan days, with skipped and moved sessions (F-21b) named as such.
  - The matching is tested.

### F-31 · Other sports count
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Pace Off reads runs, and strength only to tick off a plan session. A 90-minute ride yesterday is invisible, so today's prescription pushes as if the runner had rested. 54% of Strava's users log two sports or more and 60.6% of surveyed runners lift weights. Garmin's users complain that its per-sport coaches don't combine; Runna plans no other sport at all.
- **Defaults (the owner can change them here):**
  - Every workout type is read (the workout permission already covers them) and shown in the week screen.
  - Another sport's workout of 45 minutes or more yesterday counts as activity yesterday: no skip, and no push above the baseline or the plan's easy distance today. The reasoning names it: "Yesterday's 90-minute ride counts: easy today."
  - It never ticks off a plan run.
  - No plans for other sports.
- **Done when:** `HealthKitService` and the snapshot carry other workouts; `DayPrescription` and `PushTargetEngine` take them, with tests; the week screen lists them.

### F-30 · Shoes
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Runners track shoe mileage in Strava or Garmin, where the alert is an email set up on a website, or one default pair per activity type. A coach that knows the session can do better. In a cohort of 264 runners, those who rotated pairs had a 39% lower injury hazard (observational).
- **Defaults (the owner can change them here):**
  - Pairs are added in Profile: a name, a start date, a retire-at distance (700 km by default).
  - A run gets a pair by rule: a default pair for easy and long runs, one for quality sessions, one for races. Run detail can change it.
  - Profile shows each pair's distance and the weeks left at the current mileage. One notification at 90%.
- **Done when:** `shoes.json` in the App Group container (in `AppGroup.containerFiles`), the run-to-pair link in the ledger, a pure, tested assignment and projection, and the Profile and run detail rows.

### F-25 · A time goal, and a prediction that shows its range
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The prediction is one time, from Riegel's formula with exponent 1.06 on the best run of the last 60 days. On 2,303 recreational runners that formula holds up to the half marathon and gives half of marathoners a time at least 10 minutes too fast. The goal has a distance and a date but no time, so the app can't say whether "under 1:50" is in reach. Runna's most criticised point is that an ambitious time makes every session too fast.
- **Defaults (the owner can change them here):**
  - The goal takes an optional target time.
  - The prediction is a range, wider with fewer runs behind it.
  - For the marathon the exponent follows the runner's weekly distance over the last 8 weeks: 1.06 at 65 km a week or more, 1.10 at 30 km or less, a straight line between.
  - The target is judged against the range and the improvement the prediction already projects to race day: in reach, ambitious, or out of reach this time.
  - Plan paces never come from the target, only from current fitness (F-17).
- **Done when:** the range and the verdict are pure and tested; Profile's prediction card and the plan's detail show them.

### F-07 · Pacing intelligence in the prediction
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** The per-kilometre fade analysis exists but doesn't feed the race prediction.
- **Where:** `PaceOffShared/PaceDecayAnalyser.swift`, `GoalPredictionService`.
- **Done when:**
  - A consistent late-run fade adjusts the projection, shown as one annotation on the prediction.
  - Tests cover it.

### F-24 · After the race
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** A plan ends on race day and then there is nothing. Today falls back to the daily target, which knows nothing of a marathon two days ago, and the Plan tab shows the picker. Activity that rose during a build-up falls back after the event.
- **Defaults (the owner can change them here):**
  - The plan appends a recovery block after the race: 1 week after a 5K or 10K, 2 after a half, 3 after a marathon. Rest on the first days (1, 1, 2, 3), then easy runs only, rising to about half the peak week. No hard session.
  - The race's result, read from Health, shows beside the prediction it beat or missed.
  - When the block ends, the Plan tab asks what's next: the next distance up, the same distance faster, or just keep running.
- **Done when:** generator tests for each goal; the Plan tab and Today show the block; the result card.

### F-32 · Strength that progresses
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** A strength session is the same exercise list from the first week to the taper, with no load guidance. Heavy loads (80% of one-rep maximum and up) and plyometrics improve running economy; lighter work doesn't. Fewer injuries are shown only for programmes that were supervised or done consistently, hip and core work among them.
- **Defaults (the owner can change them here):**
  - Three phases across a plan: learn the movements (more reps, light), build (fewer reps, heavy), keep (taper).
  - Medium and Aggressive plans add a short plyometric block (hops, bounds, skips) in the build phase.
  - Every session ends with a hip-and-core finisher.
  - The copy says strength improves running economy and may lower injury risk when done consistently. Nothing stronger.
- **Done when:** the generator's session templates by phase, with tests; the plan detail shows the phase and the load cue.

### F-27 · Training load, described
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Pace Off shows distance, so a week of hard sessions and a week of jogging look the same. Garmin, COROS and Polar set the last 7 days' load against the last 4 to 6 weeks, and Strava charges for its load calendar. The evidence doesn't support a load ratio as injury protection: the acute:chronic ratio failed that test, and in the BJSM 2025 cohort a higher ratio went with fewer injuries.
- **Defaults (the owner can change them here):**
  - A run's load is its minutes weighted by heart-rate zone (zone 1 ×1 to zone 5 ×5, F-15's zones), or minutes ×2 without heart rate. Other workouts count once F-31 exists.
  - Trends shows this week's load against the average of the four before: "A normal week", "A big week: 38% over your usual", "A light week".
  - No risk colour, and no advice derived from the ratio.
- **Done when:** the load and the comparison are pure and tested; Trends and the week screen show them; SPEC's scope note on load says the same.

### F-26 · HRV as a trend
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Readiness compares one night's HRV with the 30-day baseline. Single Apple Watch readings carry about 29% error, and a reliable weekly figure needs 5 nights of 7. One low reading can turn the day yellow.
- **Defaults (the owner can change them here):**
  - The HRV signal is the mean of the last 7 days' readings when at least 5 days have one, against the 30-day baseline. With fewer, today's rule.
  - iOS 27 adds an RMSSD type, the measure the HRV-guided studies use. When the SDK that CI builds with has it, read it behind `#available`, keep its baseline apart from SDNN's (the two aren't comparable) and prefer it once it has 14 days.
- **Where:** `ReadinessEngine`, `HeartTrend`, `HealthKitService.fetchHRVSeries`.
- **Done when:** engine tests (one low night among normal ones stays green; five low nights turn yellow); the HRV screen draws the 7-day line; the readiness screen says which measure is in use.

### F-28 · Hills in the pace
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** A hilly easy run reads as slow and a downhill one as fast: the splits, the pacing headline and the run review (F-19a) judge raw pace. Strava and Garmin show a grade-adjusted pace.
- **Done when:**
  - A pure function gives each km's grade-adjusted pace from the elevation profile, using the published energy cost of running on a gradient (Minetti 2002: 3.40 J/kg/m on the flat, 1.73 at −20%, 18.93 at +45%).
  - Run detail's splits show it beside the pace when the run has elevation.
  - The run review compares the adjusted pace with the band.
  - Tests: flat, uphill, downhill and noisy elevation.

### F-29 · Years, not weeks
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** History reads one year of runs and Trends at most 12 weeks. There's no yearly total and no way to look at three years of training.
- **Done when:**
  - History pages back through every year Health holds, fetching older years when they're scrolled to, not at launch.
  - Trends' cards take 3 months, 1 year or all.
  - A year row shows distance, runs and the longest run.

### F-33 · The same session on a treadmill
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** Plan paces are per km; a treadmill shows speed. On a belt a 1% incline matches the oxygen cost of running outdoors between 10.5 and 18 km/h.
- **Done when:** a plan workout's detail shows its blocks (F-12a) as speeds in the runner's unit (F-01), with "set 1% incline" for steady running; the conversion is tested.

### F-34 · Share cards
- **Status:** todo
- **Size:** M   ·   **Merge:** auto
- **Problem:** Nothing can be shared. A feed needs a server and puts a comparison in front of runners that some of them, the injured above all, feel as pressure. What the research supports is encouragement from people the runner knows.
- **Defaults (the owner can change them here):**
  - A card is drawn on the phone for a run, a week, a new best and a finished plan: distance, pace, the verdict, the brand track.
  - The route shows as a shape without a map, with its first and last 200 m left out, so a card never gives away a home address.
  - It goes out through the share sheet. Nothing is uploaded by us.
- **Done when:** the cards render from the ledger and Health in Light and Dark Mode; the route trimming is a pure, tested function.

### F-06 · Haptics
- **Status:** todo
- **Size:** S   ·   **Merge:** auto
- **Problem:** No haptic feedback anywhere (PRD §11).
- **Done when:** `sensoryFeedback` fires on target hit, plan selected and onboarding complete.

---

## Step 3 · Completeness: race day, and new ground

### F-35 · Race day
- **Status:** todo
- **Size:** L   ·   **Merge:** auto
- **Problem:** Race day is one push and a line in the plan. Apple's Pacer gives a flat target pace; Garmin's PacePro gives each stretch of a course its own. In four million marathon results 28% of men and 17% of women hit the wall, and runners who ran the first half above 94% of their critical speed were more likely to slow by over 25% in the second. Apple Watch has no fuelling reminder.
- **Sub-items:**
  - **F-35a · A pacing plan for the course** (M): the runner imports the race's GPX from Files or the share sheet. A pure function cuts it into stretches by gradient and gives each a pace (F-28's cost curve) so that they add up to the goal time, with a first half no faster than even effort. Shown as a table, and sent to the watch as steps (F-12).
  - **F-35b · Fuel for long runs and the race** (M): from the planned duration: up to 60 g of carbohydrate an hour for 2 to 3 hours, up to 90 g an hour beyond that, from glucose and fructose together. 120 g isn't shown to be better. Long runs over 90 minutes and the race plan carry the line. No calorie tracking.
  - **F-35c · Race week** (M): the week before the race, the evening push asks for an earlier night (more sleep is one of the two sleep measures shown to help athletes), and the race-day push carries the plan: start time, the first stretch's pace, the fuel.

### Parked

Ideas the research raised that aren't worth a slot yet. Each needs a reason to come back.

- **A Hyrox goal, the running half.** Over 1.5 million took part in the 2025/26 season and running is about half the race time. Pace Off could offer repeats at threshold between strength stations; a real Hyrox plan needs station work it has no way to coach.
- **Fuel and cadence cues during the run.** Both need a workout session of our own (D-10).
- **A personal heat response** from the temperature and heart rate of past runs. Plausible, untested.
- **Air quality.** WeatherKit has no such data set.
- **Symptom tags for the menstrual cycle** on the morning question (F-20). The evidence supports adjusting to how the runner feels, which F-20 already does, and doesn't support plans by cycle phase.

---

## Needs a decision (the loop never starts these)

D-04 (Live Activity) is now part of D-10, and D-05 (buddy pairing) is D-09.

### D-01 · Apple Watch: fix or hide
- **Status:** decision
- **Problem:**
  - The App Group doesn't sync between phone and watch, so a real watch always shows "—".
  - The post-run screen never appears, and cadence is always empty.
- **Options:** fix it with WatchConnectivity, the post-run screen and route recording (about a week of work), or hide the broken parts while the watch is deprioritized.
- **Recommendation (2026-11-12):** hide it. Once F-12b has run on a real watch, leave our watch app out of the release and keep the target building. A watch app of our own comes back only with D-10.

### D-02 · Is Sign in with Apple optional?
- **Status:** decision
- **Problem:** CLAUDE.md and SPEC say it's optional, but the code has no way past it, and the next screen says "No accounts".
- **Options:** add a "Continue without an account" path, or make the docs say it's required.
- **Recommendation (2026-11-12):** optional. App Review expects an app without significant account-based features to work without a login, and nothing in Pace Off uses the account.

### D-03 · Legal text and privacy URL
- **Status:** decision
- **Problem:** The Legal screen still shows "Placeholder copy", and App Store submission needs a privacy policy URL. An app that uses HealthKit must have a privacy policy.
- **Options:** counsel-reviewed text, plus a public Pace Off privacy page on nextcute.com, which today only opens the Wummby legal URLs without the password.

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
- **Recommendation (2026-11-12):** offer it, with F-21a's preview. Never rebuild silently.

### D-08 · Keep the plan and settings when the app is reinstalled
- **Status:** decision
- **Problem:** Profile, plan, shoes and the ledger live only in the App Group container. A new phone restored from a backup keeps them; deleting the app loses them.
- **Options:**
  - Nothing: the iPhone's own backup covers a new phone.
  - iCloud key-value store (1 MB, an entitlement and nothing else) for profile, goal, settings and the active plan.
  - A private CloudKit database with `CKSyncEngine`.
- **The rule either way:** nothing read from HealthKit, and nothing derived from it, goes to iCloud. App Review Guideline 5.1.3(ii) forbids storing personal health information there, and Apple hasn't said where that line runs (`ARCHITECTURE.md`, "The iCloud rule").
- **Recommendation (2026-11-12):** nothing for now. The key-value store when runners ask for it.

### D-09 · A private circle: a running buddy, a small group
- **Status:** decision
- **Problem:** Encouragement from people a runner knows is among the most useful social features in the research, and competing with strangers among the weakest. SPEC's buddy proposals (B and C) need CloudKit.
- **Options:** `CKShare` (up to 100 people, each with iCloud) for counts only, such as runs done of those planned this week; Game Center challenges and leaderboards among friends (OS 26 and later); or share cards alone (F-34).
- **Open with Apple:** whether even a count of runs is "personal health information" under Guideline 5.1.3(ii), and whether App Review accepts Game Center in a fitness app. Book an App Review consultation before building.
- **Recommendation (2026-11-12):** after the first release. Share cards cover sharing until then.

### D-10 · Recording a run in Pace Off
- **Status:** decision
- **Problem:** Pace Off does nothing during the run. Recording on iPhone, a Live Activity on the Lock Screen (the old D-04) and audio cues that know the plan would fill that, and would reverse the PRD, which leaves the run to Apple's apps.
- **For:** 72% of Strava's users recorded with a phone in 2025. Since iOS 26 a workout session runs on iPhone with a Live Activity. Cues that know the plan ("this rep is 6 seconds faster than threshold") need a session of our own, because Workout Buddy can't be driven; reviewers find Workout Buddy pleasant and shallow.
- **Against:** GPS, battery, pause and crash recovery are a large surface for one developer, and F-12 already serves Apple Watch owners.
- **Recommendation (2026-11-12):** decide after F-12 has been in use for a few weeks.

### D-11 · Price
- **Status:** decision
- **Problem:** No pricing decision exists. StoreKit 2 verifies purchases on the device, so neither a one-time purchase nor a subscription needs a server.
- **What the research shows:** the median yearly app subscription renews at 25%; 66.9% of US adults have wanted to cancel one; every paywall added later drew a backlash; one-time purchases are rare among fitness apps; no survey of what runners would pay was found.
- **Options:** free; a free core with a one-time unlock; a subscription.
- **Recommendation (2026-11-12):** launch free, say that what is free stays free, and decide on a one-time supporter unlock after launch.

### D-12 · Change the plan in a sentence
- **Status:** decision
- **Problem:** The second Apple Intelligence feature. "I'm away Thursday to Sunday, next week only three runs fit" becomes a typed command (skip, move, pause, with dates) through the on-device model's guided generation; the plan's own rules check it; the runner sees a preview and confirms. One field and one answer, not a conversation, but close to the chat surface `CLAUDE.md` rules out.
- **Needs:** F-21.
- **Recommendation (2026-11-12):** yes, after F-21, in English first.

### D-13 · A longer review on Private Cloud Compute
- **Status:** decision
- **Problem:** The third Apple Intelligence feature: a weekly or end-of-block review with a 32,000-token window on Apple's Private Cloud Compute (iOS 27). The text leaves the phone for Apple's servers, each runner has a daily quota, availability in the EU is unknown, and Apple doesn't say whether text derived from HealthKit may be sent under the licence's health clause.
- **Recommendation (2026-11-12):** not now. Ask Apple the licence question first.

### D-14 · Runners with a Garmin, COROS or Polar watch, and Android
- **Status:** decision
- **Problem:** These watches write workouts to Apple Health without the route or with sparse heart rate, and without HRV. Their owners get weekly distance and plan completion from Pace Off, and no map, splits or readiness. Garmin's developer programme takes organisations only and delivers to an HTTPS endpoint, which is a server. Android can't be reached at all.
- **Options:** say so in onboarding and serve them with what Health has; add a FIT or GPX import from the share sheet (no server; untried); or build a backend for Garmin's API (`ARCHITECTURE.md`, Ring 3).
- **Recommendation (2026-11-12):** the first now, the import when runners ask, the backend only with evidence of demand.

### D-15 · Marathon long runs and marathon-pace sessions
- **Status:** decision
- **Problem:** The marathon long run peaks at 20.3 / 23.7 / 27.6 km (Easy / Medium / Aggressive), set by R-05's cap on the long run's share of the week, and no plan uses the marathon-pace or tempo sessions the model already has (`WorkoutKind.marathonPace`, `.tempo`). An Easy-tier runner meets the last 22 km for the first time in the race. R-05 capped the share because that was the load rule then. R-11's rule is the one the evidence supports, and under it a long run can grow step by step.
- **Options:**
  - Keep the plans as they are.
  - Let marathon long runs build by at most 10% a step from the runner's longest run, with every fourth week cut back, to 28 / 30 / 32 km and never past 3 hours at the slow end of the easy band; the week grows by the difference, within the 10% weekly ramp. Medium and Aggressive run the last third of every second long run at marathon pace from mid-plan.
- **Evidence:** the research found nothing on whether today's peaks are enough. The numbers in the second option follow common marathon plans (Higdon 32 km, Pfitzinger 32–35 km, Hansons 26 km), not a study. A coach's review of the templates would be worth having.
- **Recommendation (2026-11-12):** the second option, after R-11 and F-21a.

---

## Not building

What the research says to leave out, so the question doesn't come back each month.

- **A public feed, clubs, segments and leaderboards among strangers.** They need a server, moderation and anti-cheat, and Strava owns the field: 58.3% of surveyed runners use it.
- **Strava integration.** Since June 2026 its API stops a self-service app at ten athletes, bans AI use of the data and shows a runner's data only to that runner. Runs reach Strava from the app that recorded them.
- **Routes by popularity and heatmaps.** They need other runners' data on a server. Apple Maps' custom routes are free and work offline on the watch.
- **Plans for triathlon, cycling or swimming.** No running-first app plans them, and nothing shows runners need them from a running coach. Other sports count toward the day instead (F-31).
- **Plans by menstrual-cycle phase.** The best meta-analysis finds a trivial effect on low-quality evidence.
- **Continuous glucose data.** There is no agreed reading of it for athletes without diabetes.
- **The acute:chronic load ratio as a safety gauge.** It failed that test (F-27 describes load instead).
- **Form targets** for ground contact time or vertical oscillation. Only a cadence cue is defensible, and it needs D-10.
- **A race catalogue.** It is a server-side database. The runner enters the race.
- **A third-party cloud LLM.** It needs a server for the key, explicit permission and a new privacy label, and the on-device model is free.

---

## Earlier · The owner's request of 2026-11-08

Requests the owner put ahead of the waves on 2026-11-08, in their order. All but F-10b are done; F-12 to F-16, picked from Claude's suggestions then, are now in Step 1, and F-10 is in Step 2.

0. **First, every remaining fix** (owner, 2026-11-08: "csináld meg az összes javítást loop-ban, nem kell approval"). Wave 1's R-05 and R-07b, Wave 2's Q-02 to Q-11, then R-05b and Q-12 (found in R-05b). The two blocked calls were Claude's to make; each item records the decision and the owner can reverse it.
1. The app in TestFlight (T-01).
2. Every card on Today opens a detail screen (F-09).
3. A morning weather check that says what to run and when (F-10).
4. Kettlebell or free-weight cross training in the plan (F-11).
5. From Claude's suggestions, picked by the owner: F-12 to F-16.

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

### F-11 · Cross training: kettlebell or free weights in the plan
- **Status:** done (F-11a PR #49, F-11b PR #50, F-11c PR #51)
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
  - **F-11a · Plan model and generator** (M, `auto`), **done (PR #49)**: the cross-training choice on `TrainingPlanInputs` and `TrainingPlan` (`crossTraining`), a day's session (`TrainingDay.strength`), placement, session templates and the taper, all in `TrainingPlanGenerator` with tests.
  - **F-11b · Showing it** (M, `auto`), **done (PR #50)**: the picker option, the Plan tab and plan detail rows, Today's plan line, the push text and the widget.
  - **F-11c · Done from Health** (M, `auto`), **done (PR #51)**: `HealthKitService` reads strength workouts (traditional and functional strength training; workouts are already readable, so no new permission) and `TrainingPlanReconciler` ticks the session off. With that, two things F-11b left open: the widget dot stays green on a strength-only day only once the session is done, and on a run day with strength, finishing the run leaves an afternoon reminder for the session until it's logged.
- **Decisions (Claude, 2026-11-10, F-11a; the owner can reverse them):**
  - A session is an optional `TrainingDay.strength` beside the day's run, not a `WorkoutKind.strength`: a day has one workout, and a session paired with an easy run needs both on the same day. A strength-only day stays a `.rest` run day, so the push, completion and widget logic for runs is unchanged.
  - The Aggressive week has two sessions as asked, but its rest and easy days all sit before a quality session or the long run but one. So the second session follows a quality session ("hard days hard"), never the day before one: with the long run on Sunday, Tuesday after the threshold session, and Friday. The other way out would be one session for Aggressive.

---

## Earlier · Wave 1 · Fixes (critical)

These told the runner the wrong thing or prescribed too much load. All done.

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
- **Status:** done (PR #34)
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
- **Status:** done (PR #35)
- **Decision (Claude, 2026-11-08, on the owner's "nem kell approval"):** option (a), start the plan later so it ends on race day. It's how race plans usually work, it keeps the plan's length the one the goal needs, and the weeks before it aren't empty: Today's daily target keeps the runner going. (b) base-building weeks before the build would make a plan of any length, up to a year; the owner can switch to it here.
- **Size:** S   ·   **Merge:** auto
- **Problem:** The goal date is the race only when the plan's weeks can reach it (R-07a). A closer race ends the plan; a farther one doesn't.
- **Where:** `TrainingPlanGenerator.generate` (`raceDay`, `start`), `planWeeks(for:goalDate:today:)`; `PlanTabView` before a plan starts.
- **Done when:**
  - For any future race date, the plan has the race on its date.
  - If the plan starts later, the Plan tab says when.

### R-05b · The run before the long run is nearly as long as it
- **Status:** done (PR #46)
- **Size:** M   ·   **Merge:** auto
- **Problem:** R-05 moved the long run's cut into the two easy runs, so the Medium and Aggressive marathon's easy runs peak at 16.7 and 20.3 km against long runs of 22.3 and 25.5 km. One of them is the day before the long run: a 20 km Saturday, then 25.5 km on Sunday. The weekend is still lighter than before R-05 (45.8 km against 51.5), so it waits behind Wave 2. Found in R-05's review.
- **Why not just cap the easy runs:** with the quality sessions at today's fixed 8–10 km, capping the day-before run at 60% and the other at 80% of the long run, while the long run keeps its share, forces the long run down to about 20 km for the Aggressive marathon and 17.5 km for the Medium, and the peak week from 85 to 68 km. The quality sessions are what's short: marathoners run longer threshold and interval sessions.
- **Where:** `TrainingPlanGenerator` (`thresholdMeters`, `intervalMeters`, session notes, `peakRuns`, `buildWeek` / `materialise`: distances are per kind today, not per slot).
- **Done when:**
  - Half and marathon quality sessions are longer, with notes that add up to their distance: about 11 / 10 km for the half's threshold / intervals and 14 / 12 km for the marathon's (Aggressive; Medium's single session 12 km for the marathon, 9 for the half).
  - The easy run on the day before the long run is at most 60% of that week's long run; the other easy run takes what it gives up, up to 80% of the long run. With the longer sessions nothing needs dropping in the marathon and half tiers; if anything still doesn't fit, it's dropped, and no week grows.
  - R-05's share cap still holds; 5K and 10K plans, already within these limits, don't change.
  - Tests cover every goal × tier, and long-run days other than Sunday.
  - Also: a plan too short to build from a low week 1 toward race distance (a beginner's marathon eight weeks out peaks near 12 km) says so on the plan's detail screen.
- **Decision (Claude, 2026-11-08; the owner can reverse it):** "5K and 10K plans, already within these limits" was wrong: their easy runs are 74–100% of the long run (a 10 km Saturday before a 10 km Sunday in the Aggressive 5K). Their long runs are 8–16 km, where an easy run near that length the day before is no load problem, so the 60/80 rule applies to the half and the marathon only and 5K/10K plans don't change. To reverse it, drop the goal check in `TrainingPlanGenerator.peakRuns`: the 5K/10K weeks then lose up to 6 km.

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

## Earlier · Wave 2 · Quality

All done.

### Q-01 · Notification "Not now" asks for permission anyway
- **Status:** done (PR #28)
- **Size:** S   ·   **Merge:** auto
- **Problem:** On the onboarding notifications step, "Not now" triggers the same system prompt as "Allow".
- **Where:** `PaceOff/Views/Onboarding/OnboardingFlow.swift` (`secondaryTitle: "Not now"`, `onSecondary: { … onAllow() }`).
- **Done when:** "Not now" moves on without requesting authorization, and the app still works without it.

### Q-02 · Sign in asks for an email it never uses
- **Status:** done (PR #36)
- **Size:** S   ·   **Merge:** auto
- **Problem:** Sign in with Apple requests the email scope, but nothing uses it.
- **Where:** `PaceOff/Views/AuthGateView.swift` (`requestedScopes = [.fullName, .email]`).
- **Done when:** only `.fullName` is requested, and nothing reads an email.

### Q-03 · No empty state for a new runner
- **Status:** done (PR #37)
- **Size:** M   ·   **Merge:** auto
- **Problem:** With no runs, or with Health access denied, Today shows a 3 km restart target and a skip count, and the evening "Last call" fires.
- **Where:** `TodayViewModel`, `TodayView`, `PushTargetEngine` with zero runs, `NotificationScheduler`.
- **Done when:**
  - With no runs, Today shows a first-run card: what Pace Off needs and how to log a first run, with a link to Health settings when access is denied.
  - There is no target and no pushes until there is data.
  - Tests cover the engine's no-data case.

### Q-04 · The PB isn't tied to a distance
- **Status:** done (PR #38)
- **Size:** M   ·   **Merge:** auto
- **Problem:** When the goal changes, the old PB stays, so a 10K time is used as a half-marathon time in the prediction and the plan paces.
- **Where:** `UserProfile.personalBest`, `ProfileStore`, `GoalPredictionService`, `TrainingPlanGenerator` inputs, `ProfileEditView`.
- **Done when:**
  - A PB stores its distance. A stored PB without one is migrated as the current goal's.
  - A PB for another distance is converted through VDOT, never used raw.
  - Tests cover the conversion and the migration.

### Q-05 · VO₂ max explanation is backwards, and the trend is noisy
- **Status:** done (PR #39)
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
- **Status:** done (PR #40)
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
- **Status:** done (PR #41)
- **Size:** M   ·   **Merge:** auto
- **Problem:** The Health observer is never started, so the afternoon reminder still fires after a run until the app is opened. The background task also doesn't end cleanly when it expires.
- **Where:** `HealthKitService.startObservingVO2Max` is defined but never called; there's no workout observer; `BackgroundRefreshService` has no `expirationHandler`. The background-delivery entitlement is already in `PaceOff.entitlements`.
- **Done when:**
  - Observers on workouts and VO₂ max start at launch with background delivery.
  - When an observer fires, the app re-syncs, reschedules the pushes and reloads the widget.
  - The BG task cancels its work and completes in its expiration handler.

### Q-08 · Delete my data, and a complete sign-out
- **Status:** done (PR #42)
- **Size:** M   ·   **Merge:** auto
- **Problem:** SPEC promises "delete my data", but it doesn't exist. Sign-out leaves the widget data, scheduled notifications and settings behind.
- **Where:** `ProfileStore.signOut()`, `ProfileView`, `AppGroup`, `NotificationScheduler`, the widget.
- **Done when:**
  - Profile has "Delete my data". It clears every App Group key and container file, cancels notifications, reloads the widget and returns to the start.
  - Sign-out does the same.
  - SPEC § E matches.

### Q-09 · Profile repeats itself; Trends has no empty states
- **Status:** done (PR #43)
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
- **Status:** done (PR #44)
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
- **Status:** done (PR #45)
- **Size:** S   ·   **Merge:** auto
- **Problem:** The cached snapshot stores yesterday's HRV and average heart rate as plain numbers. When Today renders a cache synced on an earlier day (cold launch, or a sync that kept the cache), the morning check-in card shows those values as yesterday's, though they belong to the day before the sync.
- **Where:** `HealthDataSnapshot.yesterdayHRV` / `yesterdayAvgHeartRate` (`PaceOffShared/HealthDataCache.swift`); `TodayViewModel.applySnapshot`; the check-in card.
- **Done when:**
  - Day-relative values from a snapshot synced on an earlier calendar day aren't shown as yesterday's. Either hide them, or label them with their day.
  - A pure check with tests decides it.

### Q-12 · Session notes describe the peak session in every week
- **Status:** done (PR #47)
- **Size:** S   ·   **Merge:** auto
- **Problem:** A quality session's distance follows the week's volume (70% in week 1, 30% in race week), but its notes always describe the peak session: week 1's 9.8 km marathon threshold says "WU 3 km · 5 × 1.6 km @ T w/ 250 m jog · CD 2 km", which is 14 km. Found in R-05b.
- **Where:** `TrainingPlanGenerator` (`thresholdNotes`, `intervalNotes`, `materialise`).
- **Done when:**
  - Each week's session is the peak session cut to its distance: fewer reps, never a larger share of the session than at the peak, with the warm-up and cool-down taking the rest. Its notes add up to its distance (to the tenth of a km they show) in every week, 5K and 10K included.
  - A session's distance comes from its parts, so the two can't drift apart; 5K and 10K sessions keep their distances.
  - Tests over every goal × tier × week, full-length, low-start and race-date plans.

---

## Visual check queue

The loop works in a cloud session with no simulator: CI proves a change compiles and the tests pass, not how it looks. Every merged PR that changes UI is added here. The owner ticks it after a look on a device, in Light and Dark Mode.

- [ ] PR #51: on a strength-only day, the widget dot stays orange/red until a strength workout is in Health, then green with "Strength: … ✓"; after a run on a strength day, the 17:30 push "Run done. Strength left today: …"
- [ ] PR #50: the plan picker's Cross training control and the "N strength/wk" chip; the plan detail's strength rows (preview "Plan detail — Medium half with kettlebell"); the Plan tab hero on a strength day and the week rows; Plan Settings' Cross training row; Today's plan line on a strength day; the widget's "Strength: Kettlebell · 35 min" (systemSmall preview)
- [ ] PR #47: plan detail session notes in week 1, mid-build and race week match each session's distance (fewer reps, warm-up and cool-down to 0.1 km; one rep, no jog, in race week)
- [ ] PR #46: the plan detail's orange "too few weeks" line (preview "Plan detail — beginner's marathon, 8 weeks"); half and marathon plans' longer threshold and interval sessions with their notes, and the shorter Saturday easy run before a Sunday long run
- [ ] PR #45: Today's HRV and Resting HR cards: "Yesterday" / "Avg yesterday 58 bpm" after a sync today; after a cold launch on a cache from an earlier day, the weekday ("Thursday", "Avg Thursday 58 bpm"); a week-old cache shows no yesterday values
- [ ] PR #44: at the largest accessibility text size: Today's hero, Plan, Week, VO₂ max, Heart trend and Run detail heroes, Profile's goal card, onboarding; onboarding with Reduce Motion; VoiceOver on the profile-photo picker
- [ ] PR #43: Profile's hero without the chips and the goal card (PB row, race countdown with and without a prediction); Trends with no data
- [ ] PR #42: Profile's Delete My Data button and confirmation, the reworded Sign Out confirmation; on a device, onboarding starts fresh afterwards and the widget shows "Open Pace Off"
- [ ] PR #41: on a device, a run finished on Apple Watch with the phone locked stops the afternoon reminder and shows on the widget without opening the app
- [ ] PR #40: Profile → Notifications: the Daily pushes switch, the afternoon at :30, steppers greyed out when off; on a device, the permission prompt when switching on after "Not now"
- [ ] PR #39: the VO₂ max screen's trend line (falling / flat / rising / not enough readings) and its What it means copy
- [ ] PR #38: the onboarding PB step (new title, distance picker), Profile → Edit PB section, Profile's "10K PB" chip and "PB · 10K" row
- [ ] PR #37: Today with no runs (preview "Today (first run)"): the Log your first run card, its glass Open Health button on the blue card, and that it opens Health
- [ ] PR #35: Plan tab with a race further out than the plan (preview "Plan tab — starts later"): "Starts 3 Mar" subtitle and hero, the First week card with no day marked, the Starts row; the plan detail's start line and Settings → Starts
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

- 2026-11-12 · R-12: an Apple Intelligence rewording is shown only when it carries exactly the canned line's numbers (`NarrationCheck`); accepted rewordings are reused, and the background refresh no longer calls the model (PR #53)
- 2026-11-12 · Roadmap re-ordered after the competitor research: Steps 0 to 3 replace the waves, with the no-backend architecture plan (`ARCHITECTURE.md`) and the research report (`docs/research-2026-11.md`); no code changed (PR #52)
- 2026-11-11 · F-11c: a strength workout in Health ticks off the plan's session: it leaves the pushes, a run day with the session still to do gets one afternoon reminder, and the widget dot waits for it on a strength-only day (PR #51)
- 2026-11-10 · F-11b: strength sessions show in the plan picker (Cross training), plan detail, Plan tab, Plan Settings, Today's plan line, the pushes and the widget (PR #50)
- 2026-11-10 · F-11a: plans can carry kettlebell or free-weight sessions (1 a week Easy, 2 Medium and Aggressive), placed on free days by the rules, easing off in the taper; in the model only until F-11b shows them (PR #49)
- 2026-11-09 · F-10a: RunWindowPlanner picks when to run from an hourly forecast (rain, heat or cold, wind, darkness, in that order) with the morning push's reason line; not wired up until F-10b (PR #48)
- 2026-11-08 · Q-12: a quality session below the peak is the peak session cut to its distance, so its notes add up in every week (PR #47)
- 2026-11-08 · R-05b: half and marathon quality sessions are longer, the easy run before the long run keeps to 60% of it and the other to 80%, and a plan that can't build far says so (PR #46)
- 2026-11-08 · Q-11: yesterday's HRV and average heart rate name their own day when the cached snapshot was synced on an earlier day, and hide from a week back (PR #45)
- 2026-11-08 · Q-10: the big custom font sizes follow Dynamic Type (scaledFont), the photo picker has a VoiceOver label, and repeating or sliding animations respect Reduce Motion (PR #44)
- 2026-11-08 · Q-09: Profile shows the goal, PB and race day once and refreshes its prediction after a Health sync; Trends cards have empty states (PR #43)
- 2026-11-08 · Q-08: Profile has Delete My Data; it and sign-out erase every App Group key and file, cancel every push and reset the widget (PR #42)
- 2026-11-08 · Q-07: Health observers on workouts and VO₂ max wake the app for a new run; an expiring background task completes from its handler (PR #41)
- 2026-11-08 · Q-06: notification settings show the times pushes fire at, get an on/off switch, and reschedule at once (PR #40)
- 2026-11-08 · Q-05: the VO₂ max trend needs 3 readings over 14 days and a change beyond noise before it moves the target; the VO₂ max screen reads the same rule (PR #39)
- 2026-11-08 · Q-04: the PB records its distance; a PB for another distance converts through VDOT for the plan and the prediction (PR #38)
- 2026-11-08 · Q-03: no target and no pushes until Health holds a run; Today shows how to log a first run instead (PR #37)
- 2026-11-08 · Q-02: Sign in with Apple asks only for the name, never the email (PR #36)
- 2026-11-08 · R-07b: a race further out than the plan starts the plan later, so it ends on race day; the Plan tab says when it starts (PR #35)
- 2026-11-08 · R-05: the long run takes at most 45 / 35 / 30% of a week with three / four / five runs, the cut going to the easy runs; week 1 starts from the runner's longest recent run (PR #34)
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
