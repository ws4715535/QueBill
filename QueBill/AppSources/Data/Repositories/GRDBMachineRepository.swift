import Foundation
import GRDB

actor GRDBMachineRepository: MachineRepository {
    private let database: AppDatabase
    private let seedDemoData: Bool

    init(database: AppDatabase, seedDemoData: Bool = true) {
        self.database = database
        self.seedDemoData = seedDemoData
    }

    func seedIfNeeded() async throws {
        try await database.queue.write { db in
            guard try MachineRecord.fetchCount(db) == 0 else { return }
            guard self.seedDemoData else { return }
            for machine in Machine.demoMachines {
                try MachineRecord(machine: machine).insert(db)
            }
        }
    }

    func fetchMachines() async throws -> [Machine] {
        try await database.queue.read { db in
            try MachineRecord
                .order(Column("number").asc)
                .fetchAll(db)
                .compactMap(\.machine)
        }
    }

    func save(_ machine: Machine) async throws {
        try await database.queue.write { db in
            try MachineRecord(machine: machine).save(db)
        }
    }

    func delete(machineID: UUID) async throws {
        try await database.queue.write { db in
            try MachineRecord.deleteOne(db, key: machineID.uuidString)
        }
    }
}

private struct MachineRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "machine"

    let id: String
    let number: String
    let type: String
    let status: String
    let note: String?
    let openedAt: Date?
    let updatedAt: Date

    init(machine: Machine) {
        id = machine.id.uuidString
        number = machine.number
        type = machine.type.rawValue
        status = machine.status.rawValue
        note = machine.note
        openedAt = machine.openedAt
        updatedAt = machine.updatedAt
    }

    var machine: Machine? {
        guard
            let id = UUID(uuidString: id),
            let type = MachineType(rawValue: type),
            let status = MachineStatus(rawValue: status)
        else { return nil }

        return Machine(
            id: id,
            number: number,
            type: type,
            status: status,
            note: note,
            openedAt: openedAt,
            updatedAt: updatedAt
        )
    }
}

actor InMemoryMachineRepository: MachineRepository {
    private var machines: [Machine]

    init(machines: [Machine] = Machine.demoMachines) {
        self.machines = machines
    }

    func seedIfNeeded() async throws {}

    func fetchMachines() async throws -> [Machine] {
        machines.sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
    }

    func save(_ machine: Machine) async throws {
        guard let index = machines.firstIndex(where: { $0.id == machine.id }) else {
            machines.append(machine)
            return
        }
        machines[index] = machine
    }

    func delete(machineID: UUID) async throws {
        machines.removeAll { $0.id == machineID }
    }
}

extension Machine {
    static var demoMachines: [Machine] {
        let now = Date()
        return [
            demo("01", .fourSeat, .idle, nil, now),
            demo("02", .fourSeat, .inUse, now.addingTimeInterval(-4_680), now),
            demo("03", .eightSeat, .inUse, now.addingTimeInterval(-19_532), now),
            demo("05", .fourSeat, .idle, nil, now),
            demo("06", .eightSeat, .maintenance, nil, now, note: "维护中，当前不可操作"),
            demo("07", .fourSeat, .inUse, now.addingTimeInterval(-2_956), now),
            demo("08", .eightSeat, .idle, nil, now),
            demo("09", .fourSeat, .inUse, now.addingTimeInterval(-19_534), now)
        ]
    }

    static func demo(
        _ number: String,
        _ type: MachineType,
        _ status: MachineStatus,
        _ openedAt: Date?,
        _ updatedAt: Date,
        note: String? = nil
    ) -> Machine {
        let suffix = number.padding(toLength: 12, withPad: "0", startingAt: 0)
        return Machine(
            id: UUID(uuidString: "A0000000-0000-0000-0000-\(suffix)") ?? UUID(),
            number: number,
            type: type,
            status: status,
            note: note,
            openedAt: openedAt,
            updatedAt: updatedAt
        )
    }
}
