import XCTest

final class RunLedgerTests: XCTestCase {

    private let cal = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))!
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: today)! }

    private var dir: URL!
    private var fileURL: URL { dir.appendingPathComponent(RunLedger.filename) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func target(km: Double) -> RunTarget {
        RunTarget(distanceMeters: km * 1000, tone: .firm, daysSinceLastRun: 1, vo2MaxSlope: nil,
                  baselineMeters: km * 1000, ceilingClamped: false, fatigueGuardActive: false,
                  capMeters: km * 1400)
    }

    private func targetDay(km: Double) -> DayPrescription {
        DayPrescription.make(planStatus: nil, readiness: nil, target: target(km: km), easyPace: nil)!
    }

    private let threshold = Workout(kind: .threshold, distanceMeters: 10_000, paceMinSecPerKm: 280, paceMaxSecPerKm: 295)

    private func run(_ start: Date, km: Double, id: UUID = UUID()) -> RunRecord {
        RunRecord(id: id, startDate: start, endDate: start.addingTimeInterval(km * 330),
                  distanceMeters: km * 1000, durationSeconds: km * 330)
    }

    // MARK: - The rows

    func testWriteAndRead() async {
        let ledger = RunLedger(fileURL: fileURL)
        let morningRun = run(today.addingTimeInterval(-3600), km: 6)
        await ledger.record(prescription: targetDay(km: 6), readiness: .green, runs: [morningRun], now: today)

        let file = await RunLedger(fileURL: fileURL).load()
        let row = file.day(today, calendar: cal)
        XCTAssertEqual(row?.prescription?.kind, .run)
        XCTAssertEqual(row?.prescription?.source, .dailyTarget)
        XCTAssertEqual(row?.prescription?.distanceMeters, 6_000)
        XCTAssertEqual(row?.prescription?.readiness, .green)
        XCTAssertEqual(file.runIDs(on: today, calendar: cal), [morningRun.id])
    }

    func testALaterRefreshTheSameDayReplacesTheRow() {
        let first = RunLedgerFile().recording(prescription: targetDay(km: 6), readiness: .green, runs: [], now: today, calendar: cal)
        let later = first.recording(prescription: targetDay(km: 4), readiness: .red, runs: [],
                                    now: today.addingTimeInterval(4 * 3600), calendar: cal)
        XCTAssertEqual(later.days.count, 1)
        XCTAssertEqual(later.day(today, calendar: cal)?.prescription?.distanceMeters, 4_000)
        XCTAssertEqual(later.day(today, calendar: cal)?.prescription?.readiness, .red)
    }

    func testAPastDayIsNeverRewritten() {
        let monday = RunLedgerFile().recording(prescription: targetDay(km: 8), readiness: nil, runs: [], now: yesterday, calendar: cal)
        let tuesday = monday.recording(prescription: targetDay(km: 5), readiness: nil, runs: [], now: today, calendar: cal)
        XCTAssertEqual(tuesday.days.count, 2)
        XCTAssertEqual(tuesday.day(yesterday, calendar: cal), monday.day(yesterday, calendar: cal))
        XCTAssertEqual(tuesday.day(today, calendar: cal)?.prescription?.distanceMeters, 5_000)
    }

    func testThePrescriptionKeepsWhatChangedIt() throws {
        let status = PlanDayStatus(workout: threshold, isCompleted: false, strength: nil)
        let red = try XCTUnwrap(DayPrescription.make(planStatus: status, readiness: .red, target: nil, easyPace: 330...350))
        let file = RunLedgerFile().recording(prescription: red, readiness: .red, runs: [], now: today, calendar: cal)
        let row = try XCTUnwrap(file.day(today, calendar: cal)?.prescription)
        XCTAssertEqual(row.source, .plan)
        XCTAssertEqual(row.workoutKind, .easy)
        XCTAssertEqual(row.adjustment, .cutForRed)
        XCTAssertEqual(row.distanceMeters, 6_000)
        XCTAssertEqual(row.planDistanceMeters, 10_000)
        XCTAssertEqual(row.paceMinSecPerKm, 330)
    }

    // MARK: - The runs

    func testRunsAreFiledUnderTheirDayOnce() {
        let late = run(yesterday.addingTimeInterval(10 * 3600), km: 10)
        let now = run(today.addingTimeInterval(-3600), km: 5)
        let file = RunLedgerFile()
            .recording(prescription: nil, readiness: nil, runs: [now, late], now: today, calendar: cal)
            .recording(prescription: nil, readiness: nil, runs: [now, late], now: today, calendar: cal)
        XCTAssertEqual(file.runs.count, 2)
        XCTAssertEqual(file.runIDs(on: yesterday, calendar: cal), [late.id])
        XCTAssertEqual(file.runIDs(on: today, calendar: cal), [now.id])
    }

    func testOldRowsAreDropped() {
        let long = cal.date(byAdding: .day, value: -(RunLedgerFile.keepDays + 1), to: today)!
        let file = RunLedgerFile()
            .recording(prescription: targetDay(km: 5), readiness: nil, runs: [], now: long, calendar: cal)
            .recording(prescription: targetDay(km: 5), readiness: nil, runs: [], now: today, calendar: cal)
        XCTAssertEqual(file.days.map(\.day), [cal.startOfDay(for: today)])
    }

    // MARK: - The file

    func testACorruptFileStartsEmptyAndIsReplaced() async throws {
        try Data("not json".utf8).write(to: fileURL)
        let ledger = RunLedger(fileURL: fileURL)
        let empty = await ledger.load()
        XCTAssertEqual(empty, RunLedgerFile())
        await ledger.record(prescription: targetDay(km: 5), readiness: nil, runs: [], now: today)
        let reloaded = await ledger.load()
        XCTAssertEqual(reloaded.days.count, 1)
    }

    func testMissingFieldsDecode() throws {
        let file = try JSONDecoder().decode(RunLedgerFile.self, from: Data("{}".utf8))
        XCTAssertEqual(file, RunLedgerFile())
        let noRuns = try JSONDecoder().decode(RunLedgerFile.self, from: Data(#"{"schemaVersion": 1, "days": []}"#.utf8))
        XCTAssertEqual(noRuns.runs, [])
    }

    func testNoFileIsEmpty() async {
        let empty = await RunLedger(fileURL: fileURL).load()
        XCTAssertEqual(empty, RunLedgerFile())
        let none = await RunLedger(fileURL: nil).load()
        XCTAssertEqual(none, RunLedgerFile())
    }

    func testDeleteMyDataErasesIt() {
        XCTAssertTrue(AppGroup.containerFiles.contains(RunLedger.filename))
    }
}
