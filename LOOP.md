# The roadmap loop

How Claude develops Pace Off on its own: one iteration takes the top workable item from `ROADMAP.md` and carries it from code to a merged PR. Repeat it on a schedule and the roadmap builds itself. The owner steers by editing `ROADMAP.md`, not by watching sessions.

Read `CLAUDE.md` first; everything there applies. This file only adds the loop.

## Starting it

- **Scheduled (no one at the keyboard):** a Claude Code scheduled task that starts a fresh cloud session on this repository, with the prompt:
  > Run one iteration of LOOP.md in this repository.
- **By hand, in a Claude Code session:** say "Run one iteration of LOOP.md", or repeat it with `/loop 6h Run one iteration of LOOP.md`.

The procedure is the same either way.

## Settings

The owner can change these here.

| Setting | Value | Meaning |
|---|---|---|
| Items per run | 1 | After merging one item, stop and report. |
| Auto-merge | on | Merge a `Merge: auto` item's PR once CI is green and the self-review is clean. Off means every PR waits for the owner. |
| Fix attempts | 3 | CI fix pushes on one PR before the item is marked `blocked`. |
| Open review PRs | 2 | At most this many `Merge: review` PRs waiting for the owner. At the limit, only `auto` items are started. |
| Report language | Hungarian | The end-of-run report is for the owner. |

## One iteration

### 0 · Preflight

1. Read `CLAUDE.md`, `ROADMAP.md` and this file from the latest `origin/main`.
2. **Main must be green.** Check CI on the latest main commit. If it's red, fixing it is this run's item: diagnose from the job log, fix on your branch, PR, merge, report. Nothing else starts on a red main.
3. **Finish what's open first.** Find open PRs whose title starts with `[roadmap `. For each one that is yours to drive:
   - Red CI or a merge conflict: fix it now (step 5 rules).
   - Green and `auto`: run step 6 and merge it.
   - Green and `review`: leave it for the owner.

   If one of these took the run's item slot, report and stop.
4. **Tidy statuses:**
   - An item at `in progress (PR #n)` whose PR the owner has merged becomes `done (PR #n)`, with a Done line.
   - One whose PR was closed without merging goes back to `todo`, with a note.

   These edits ride along in this run's PR.
5. **Pick the item:** the first item from the top of `ROADMAP.md` whose status is `todo`. Skip `decision` and `blocked` items, and skip a `review` item while the review-PR limit is reached. If nothing is workable, report that and stop: don't invent work.

### 1 · Understand the item

1. Read every file in **Where**, and anything they call that the change could touch.
2. **Confirm the problem still exists** in the current code. If it's already fixed, set the status to `done (already fixed)`, add a Done line naming the commit that fixed it, ship that as a small docs PR, and pick the next item. This counts as the run's item only if it was the last one.
3. If the item is size L, split it first: replace it in `ROADMAP.md` with `R-xxa`, `R-xxb`… sub-items, each one PR, with their own **Done when**. Work on the first; the split ships in the same PR.
4. If **Done when** is ambiguous, or the right fix needs a product decision, don't guess. Set `blocked: <the question>`, ship that edit, and pick the next item.

### 2 · Branch

- In a cloud session, work on the branch the session gives you. If that branch's PR was already merged, restart it from `origin/main`.
- Otherwise, create `claude/roadmap-<id>-<slug>` from `origin/main`.
- Merge `origin/main` into it before pushing if main has moved.

### 3 · Build it

- Keep to the item's scope. If you notice other problems, add them to `ROADMAP.md` as new `todo` items in the right wave; don't fix them in this PR.
- Follow `CLAUDE.md`:
  - Observation, not `ObservableObject`.
  - Views stay dumb; logic goes in `PaceOffShared`.
  - Brand colours come from `Views/Design/`.
  - No new dependencies, CloudKit, SwiftData or servers.
- **Tests:** any change to logic in `PaceOffShared` gets unit tests in `PaceOffTests`: the bug's case first, then the fix. If a fix lives in a view or service, pull the decision out into a pure function so it can be tested.
- **New Swift files:** there is no XcodeGen in the cloud. Add each new file with `python3 scripts/pbxproj.py add <path> <target> [<target> …]`. Files under `PaceOffShared/` go into all four targets: `PaceOff`, `PaceOffWidget`, `PaceOffTests`, `"PaceOff Watch App"`. New test files go into `PaceOffTests`.
- **Docs:** if behaviour that `SPEC.md`, `README.md` or `CLAUDE.md` describes changes, update them in the same PR.
- **Roadmap:** the status edit ships in the same PR, see step 5. If the change touches UI, add a line to the **Visual check queue** too.

### 4 · Check it before pushing

There is no Swift compiler in the cloud: CI is the compiler, and every red run costs a cycle. Before each push, re-read the whole diff hunting for what would fail to build:

- Every new file is in `project.pbxproj` for the right targets. `git diff PaceOff.xcodeproj` shows it.
- Ternaries mixing style types: write `Color.white : Color.secondary`, not `.white : .secondary`.
- Memberwise-init argument order follows the property order.
- Views reading `@Environment(Type.self)` get that type injected in their `#Preview`s and in every sheet that shows them.
- APIs exist on iOS 26 / watchOS 26. When unsure, use the older API you know.
- `@MainActor` code isn't called from a nonisolated context.
- Charts and MapKit initializers use their real argument labels.
- Nothing in `PaceOffShared` imports UIKit or HealthKit.

Run what does run here: `python3 scripts/pbxproj.py` for project edits, and `plutil` or a JSON parser for any asset-catalog `Contents.json` you touched.

### 5 · Ship and drive CI

1. Commit with a message that says what changed and why, ending with the attribution lines the session gives you. Push.
2. Open a PR titled `[roadmap R-01] <what changed>`, as a draft only if the session's rules say so. The body has:
   - **Problem:** the item's problem.
   - **Change:** what and where.
   - **Tests:** what covers it.
   - **Visual check:** what to look at, or "none".
   - **Roadmap:** the item ID and its Merge mode.
3. Right after opening the PR, record it in `ROADMAP.md` on the branch, commit and push:
   - **`auto` item with auto-merge on:** set `done (PR #n)` and add the Done line, newest first: `YYYY-MM-DD · <title> (PR #n)`. It becomes true when this PR merges. If the PR ends up not merging, correct it.
   - **`review` item:** set `in progress (PR #n)`.

   The push restarts CI on the new head; that's expected.
4. Subscribe to the PR's activity and end the turn. CI results wake the session; never poll with `sleep`.
5. **On red CI:**
   1. Read the failing job's log.
   2. Reproduce the cause in the code, fix it, and push.
   3. After 3 fix attempts, stop. Set the item to `blocked: CI — <one-line cause>`, push that roadmap edit to the PR, comment the details on the PR, and report.

   Never skip or disable a test to get green.

### 6 · Self-review

When CI is green:

1. Review the PR diff adversarially, with the `code-review` skill at medium effort if the session has it.
2. Fix every confirmed correctness finding, push, and wait for green again.
3. Check each **Done when** bullet against the code, one by one. If one isn't met, it's not done: go back to step 3.

### 7 · Merge

- **`Merge: auto` with auto-merge on:** mark the PR ready, and merge it with a merge commit, as the repo does. Its roadmap edit is already in it.
- **`Merge: review`, or auto-merge off:** leave the PR open and ready for review, with the item at `in progress (PR #n)`. If auto-merge is off, the step 5 edit for an `auto` item is `in progress (PR #n)` too. The owner merges, and the next run's preflight flips the status to `done`.
- Unsubscribe from the merged PR.

### 8 · Report

End every run with a short report to the owner, in the report language:

- **Done:** item, PR link, merged or waiting for review.
- **Checks:** CI result and test count.
- **Visual check:** anything waiting for a look.
- **Blocked or skipped:** what, and why.
- **Next:** the item the next run will pick.

## Never

- Start a `decision` item, or work around one.
- Add a dependency, CloudKit, SwiftData, a server, a paywall or analytics.
- Change bundle IDs, signing, entitlements or `Info.plist` privacy strings in an `auto` PR. Those are `review`.
- Push to `main` directly, force-push a branch someone else uses, or rewrite merged history.
- Merge with red or pending CI, or with an open review thread from the owner.
- Skip, disable or weaken a test to get green.
- Delete or gut the training-plan feature (CLAUDE.md, scope discipline).
- Work on the watch app beyond keeping it building, unless an item says so.
