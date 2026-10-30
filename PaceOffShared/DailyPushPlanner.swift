// DailyPushPlanner.swift
// Decides which of the three daily pushes go out today, when, and with what
// text. Pure and Sendable: NotificationScheduler only turns the result into
// one-shot notification requests, so every rule here is unit-tested.
//
// The pushes describe one day: its target, its plan workout. They are
// always scheduled for today's date only, and only for slots still ahead,
// so text from one day can never repeat on the next. The foreground refresh
// and the background task schedule each day afresh. In case neither runs
// before tomorrow's morning slot, a next-morning push goes out too; it
// names tomorrow's plan workout at most, never today's target.

import Foundation

public struct DailyPush: Equatable, Sendable {

    public enum Slot: String, Sendable, CaseIterable {
        /// Today's target, or the plan's rest-day note.
        case morning
        /// Reminder when today's run hasn't happened yet.
        case afternoon
        /// "Last call", only in a week that already has a skipped day.
        case evening
        /// Tomorrow's morning slot, replaced by the real morning push as
        /// soon as tomorrow's first refresh runs.
        case nextMorning
    }

    public let slot: Slot
    public let fireDate: Date
    public let body: String

    public init(slot: Slot, fireDate: Date, body: String) {
        self.slot = slot
        self.fireDate = fireDate
        self.body = body
    }
}

public struct DailyPushPlanner: Sendable {

    /// Local times of the three pushes. Hours come from the notification
    /// settings; the afternoon push fires at half past its hour.
    public struct Schedule: Equatable, Sendable {
        public let morningHour: Int
        public let afternoonHour: Int
        public let eveningHour: Int

        public static let defaultMorningHour = 8
        public static let defaultAfternoonHour = 17
        public static let defaultEveningHour = 21
        public static let afternoonMinute = 30

        /// Hours outside 1…23, such as the 0 an unset setting reads as,
        /// fall back to the defaults.
        public init(morningHour: Int, afternoonHour: Int, eveningHour: Int) {
            self.morningHour = (1...23).contains(morningHour) ? morningHour : Self.defaultMorningHour
            self.afternoonHour = (1...23).contains(afternoonHour) ? afternoonHour : Self.defaultAfternoonHour
            self.eveningHour = (1...23).contains(eveningHour) ? eveningHour : Self.defaultEveningHour
        }

        public static let standard = Schedule(
            morningHour: defaultMorningHour,
            afternoonHour: defaultAfternoonHour,
            eveningHour: defaultEveningHour
        )
    }

    public struct Inputs: Sendable {
        public let now: Date
        /// Today's push line (canned `VoiceCopy` or its Apple Intelligence rewrite).
        public let body: String
        public let runs: [RunRecord]
        /// The active training plan, used to tell planned rest days from skips.
        public let plan: TrainingPlan?
        /// Today's plan status, nil without an active plan.
        public let planStatus: PlanDayStatus?
        public let schedule: Schedule

        public init(now: Date,
                    body: String,
                    runs: [RunRecord],
                    plan: TrainingPlan?,
                    planStatus: PlanDayStatus?,
                    schedule: Schedule = .standard) {
            self.now = now
            self.body = body
            self.runs = runs
            self.plan = plan
            self.planStatus = planStatus
            self.schedule = schedule
        }
    }

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Today's pushes, in firing order, leaving out slots that have passed,
    /// then the next-morning push.
    public func pushes(for inputs: Inputs) -> [DailyPush] {
        let isPlanRestDay = inputs.planStatus?.isRestDay ?? false
        let planWorkout = isPlanRestDay ? nil : inputs.planStatus?.workout
        // With a plan workout today, the day is done when that workout is;
        // without one, any run counts. A short shakeout doesn't tick off a
        // planned long run.
        let doneToday = planWorkout != nil
            ? (inputs.planStatus?.isCompleted ?? false)
            : inputs.runs.contains(where: { calendar.isDate($0.startDate, inSameDayAs: inputs.now) })

        var body = inputs.body
        if let planWorkout {
            body = "Today's plan: \(planWorkout.summary). \(body)"
        }

        var pushes: [DailyPush] = []

        if isPlanRestDay {
            pushes.append(DailyPush(
                slot: .morning,
                fireDate: time(inputs.schedule.morningHour, 0, on: inputs.now),
                body: Self.restDayBody
            ))
        } else if !doneToday {
            pushes.append(DailyPush(
                slot: .morning,
                fireDate: time(inputs.schedule.morningHour, 0, on: inputs.now),
                body: body
            ))
            pushes.append(DailyPush(
                slot: .afternoon,
                fireDate: time(inputs.schedule.afternoonHour, Schedule.afternoonMinute, on: inputs.now),
                body: "Reminder: \(body)"
            ))
            if skippedDaysThisWeek(runs: inputs.runs, plan: inputs.plan, now: inputs.now) > 0 {
                pushes.append(DailyPush(
                    slot: .evening,
                    fireDate: time(inputs.schedule.eveningHour, 0, on: inputs.now),
                    body: "Last call. \(body)"
                ))
            }
        }

        pushes = pushes.filter { $0.fireDate > inputs.now }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: inputs.now) {
            pushes.append(DailyPush(
                slot: .nextMorning,
                fireDate: time(inputs.schedule.morningHour, 0, on: tomorrow),
                body: nextMorningBody(plan: inputs.plan, tomorrow: tomorrow)
            ))
        }
        return pushes
    }

    static let restDayBody = "Rest day on your plan. Recovery is training too."
    static let newDayBody = "New day, new target. Open Pace Off to see yours."

    /// Tomorrow's plan workout when there is one, else a nudge to open the
    /// app. Today's target never carries over.
    private func nextMorningBody(plan: TrainingPlan?, tomorrow: Date) -> String {
        // Midday, so the plan's own calendar lands on the same day.
        let midday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        guard let workout = plan?.todayWorkout(today: midday) else { return Self.newDayBody }
        if workout.kind == .rest { return Self.restDayBody }
        return "Today's plan: \(workout.summary). Open Pace Off for your target."
    }

    /// Days earlier this week (Monday-based, as the training plan's weeks)
    /// without a run. A day the active plan marks as rest isn't a skip.
    public func skippedDaysThisWeek(runs: [RunRecord], plan: TrainingPlan?, now: Date) -> Int {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        guard let weekStart = mondayFirst.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let today = calendar.startOfDay(for: now)

        var skipped = 0
        var day = calendar.startOfDay(for: weekStart)
        while day < today {
            let ran = runs.contains { calendar.isDate($0.startDate, inSameDayAs: day) }
            // Midday, so the plan's own calendar lands on the same day.
            let midday = calendar.date(byAdding: .hour, value: 12, to: day) ?? day
            let plannedRest = plan?.todayWorkout(today: midday)?.kind == .rest
            if !ran && !plannedRest {
                skipped += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return skipped
    }

    private func time(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
