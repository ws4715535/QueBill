import Foundation
import GRDB

actor GRDBOrderRepository: OrderRepository {
    private let database: AppDatabase
    private let seedDemoData: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(database: AppDatabase, seedDemoData: Bool = true) {
        self.database = database
        self.seedDemoData = seedDemoData
    }

    func seedIfNeeded(machines: [Machine]) async throws {
        guard seedDemoData else { return }
        let count = try await database.queue.read { db in
            try OrderLedgerRecord.fetchCount(db)
        }
        if count > 0 {
            try await seedBillingScenariosIfNeeded(machines: machines)
            return
        }

        let now = Date()
        for machine in machines where machine.status == .inUse || machine.status == .paused {
            let startedAt = machine.openedAt ?? now
            let order = Order(
                id: deterministicUUID(prefix: "B", number: machine.number),
                machineID: machine.id,
                machineNumberSnapshot: machine.number,
                machineTypeSnapshot: machine.type,
                status: machine.status == .paused ? .paused : .active,
                playerCount: 4,
                startedAt: startedAt,
                endedAt: nil,
                businessDay: BusinessDay(orderStartedAt: startedAt),
                note: machine.note ?? "预置营业演示",
                createdAt: startedAt,
                updatedAt: now
            )
            try await save(order)
            try await save(OrderEvent(
                id: UUID(), orderID: order.id, kind: .opened,
                occurredAt: startedAt, detail: "由演示数据开台"
            ))
        }

        let completed: [(String, MachineType, TimeInterval, Decimal, PaymentMethod)] = [
            ("03", .eightSeat, 13_680, 584, .weChat),
            ("02", .fourSeat, 5_400, 58.36, .cash),
            ("09", .fourSeat, 18_900, 217.05, .alipay)
        ]
        for (index, item) in completed.enumerated() {
            let endedAt = now.addingTimeInterval(TimeInterval(-3_600 * (index + 1)))
            let startedAt = endedAt.addingTimeInterval(-item.2)
            let orderID = deterministicUUID(prefix: "C", number: item.0 + String(index))
            let order = Order(
                id: orderID,
                machineID: deterministicUUID(prefix: "A", number: item.0),
                machineNumberSnapshot: item.0,
                machineTypeSnapshot: item.1,
                status: .completed,
                playerCount: 4,
                startedAt: startedAt,
                endedAt: endedAt,
                businessDay: BusinessDay(orderStartedAt: startedAt),
                note: "历史营业演示",
                createdAt: startedAt,
                updatedAt: endedAt
            )
            let pricing = PricingConfiguration.standard
            let billID = UUID()
            let bill = Bill(
                id: billID,
                orderID: orderID,
                startedAt: startedAt,
                endedAt: endedAt,
                effectiveDuration: item.2,
                lines: [BillLine(id: UUID(), title: "历史计费", startedAt: startedAt, endedAt: endedAt, amount: item.3)],
                originalAmount: item.3,
                adjustmentAmount: 0,
                finalAmount: item.3,
                playerAmounts: Array(repeating: item.3 / 4, count: 4),
                priceRuleSnapshot: try encoder.encode(pricing),
                createdAt: endedAt
            )
            try await save(order)
            try await save(bill)
            try await save(Payment(id: UUID(), billID: billID, method: item.4, amount: item.3, status: .paid, paidAt: endedAt))
            try await save(OrderEvent(id: UUID(), orderID: orderID, kind: .paid, occurredAt: endedAt, detail: item.4.title))
        }
        try await seedBillingScenariosIfNeeded(machines: machines)
    }

    private func seedBillingScenariosIfNeeded(machines: [Machine]) async throws {
        let existingOrders = try await fetchOrders()
        guard !existingOrders.contains(where: { $0.note?.hasPrefix("计费场景") == true }) else { return }

        let scenarios = try BillingScenarioSeed.all()
        let pricing = PricingConfiguration.standard
        let billingService = StandardBillingService()
        let methods: [PaymentMethod] = [.weChat, .alipay, .cash, .memberBalance]

        for scenario in scenarios {
            let orderID = deterministicUUID(prefix: "D", number: scenario.number)
            let machine = machines.first { $0.number == scenario.machineNumber }
            let order = Order(
                id: orderID,
                machineID: machine?.id ?? deterministicUUID(prefix: "A", number: scenario.machineNumber),
                machineNumberSnapshot: scenario.machineNumber,
                machineTypeSnapshot: scenario.machineType,
                status: .completed,
                playerCount: 4,
                startedAt: scenario.startedAt,
                endedAt: scenario.endedAt,
                businessDay: BusinessDay(orderStartedAt: scenario.startedAt, calendar: .mainlandChina),
                note: "计费场景 \(scenario.number) · \(scenario.title)",
                createdAt: scenario.startedAt,
                updatedAt: scenario.endedAt
            )
            let preview = try billingService.preview(context: BillingContext(
                order: order,
                pauses: [],
                pricing: pricing,
                calculatedAt: scenario.endedAt
            ))
            let billID = deterministicUUID(prefix: "E", number: scenario.number)
            let bill = Bill(
                id: billID,
                orderID: orderID,
                startedAt: preview.startedAt,
                endedAt: preview.endedAt,
                effectiveDuration: preview.effectiveDuration,
                lines: preview.lines,
                originalAmount: preview.originalAmount,
                adjustmentAmount: 0,
                finalAmount: preview.finalAmount,
                playerAmounts: preview.playerAmounts,
                priceRuleSnapshot: preview.priceRuleSnapshot,
                createdAt: scenario.endedAt
            )
            let method = methods[((Int(scenario.number) ?? 1) - 1) % methods.count]
            try await save(order)
            try await save(bill)
            try await save(Payment(
                id: deterministicUUID(prefix: "F", number: scenario.number),
                billID: billID,
                method: method,
                amount: bill.finalAmount,
                status: .paid,
                paidAt: scenario.endedAt
            ))
            try await save(OrderEvent(
                id: UUID(), orderID: orderID, kind: .opened,
                occurredAt: scenario.startedAt, detail: scenario.title
            ))
            try await save(OrderEvent(
                id: UUID(), orderID: orderID, kind: .paid,
                occurredAt: scenario.endedAt, detail: method.title
            ))
        }
    }

    func fetchOrders() async throws -> [Order] {
        let records = try await database.queue.read { db in
            try OrderLedgerRecord.order(Column("startedAt").desc).fetchAll(db)
        }
        return records.compactMap { try? decoder.decode(Order.self, from: $0.payload) }
    }

    func fetchPauses(orderID: UUID) async throws -> [OrderPause] {
        let records = try await database.queue.read { db in
            try OrderPauseLedgerRecord
                .filter(Column("orderID") == orderID.uuidString)
                .fetchAll(db)
        }
        return records.compactMap { try? decoder.decode(OrderPause.self, from: $0.payload) }
    }

    func fetchEvents(orderID: UUID) async throws -> [OrderEvent] {
        let records = try await database.queue.read { db in
            try OrderEventLedgerRecord
                .filter(Column("orderID") == orderID.uuidString)
                .order(Column("occurredAt").desc)
                .fetchAll(db)
        }
        return records.compactMap { try? decoder.decode(OrderEvent.self, from: $0.payload) }
    }

    func fetchBill(orderID: UUID) async throws -> Bill? {
        let record = try await database.queue.read { db in
            try BillLedgerRecord.filter(Column("orderID") == orderID.uuidString).fetchOne(db)
        }
        return try record.map { try decoder.decode(Bill.self, from: $0.payload) }
    }

    func fetchPayments(billID: UUID) async throws -> [Payment] {
        let records = try await database.queue.read { db in
            try PaymentLedgerRecord.filter(Column("billID") == billID.uuidString).fetchAll(db)
        }
        return records
            .compactMap { try? decoder.decode(Payment.self, from: $0.payload) }
            .sorted { ($0.paidAt ?? .distantPast) < ($1.paidAt ?? .distantPast) }
    }

    func save(_ order: Order) async throws {
        let record = OrderLedgerRecord(
            id: order.id.uuidString,
            machineID: order.machineID.uuidString,
            status: order.status.rawValue,
            startedAt: order.startedAt,
            payload: try encoder.encode(order)
        )
        try await database.queue.write { db in try record.save(db) }
    }

    func save(_ pause: OrderPause) async throws {
        let record = OrderPauseLedgerRecord(id: pause.id.uuidString, orderID: pause.orderID.uuidString, payload: try encoder.encode(pause))
        try await database.queue.write { db in try record.save(db) }
    }

    func save(_ event: OrderEvent) async throws {
        let record = OrderEventLedgerRecord(
            id: event.id.uuidString, orderID: event.orderID.uuidString,
            occurredAt: event.occurredAt, payload: try encoder.encode(event)
        )
        try await database.queue.write { db in try record.save(db) }
    }

    func save(_ bill: Bill) async throws {
        let record = BillLedgerRecord(id: bill.id.uuidString, orderID: bill.orderID.uuidString, payload: try encoder.encode(bill))
        try await database.queue.write { db in try record.save(db) }
    }

    func save(_ payment: Payment) async throws {
        let record = PaymentLedgerRecord(id: payment.id.uuidString, billID: payment.billID.uuidString, payload: try encoder.encode(payment))
        try await database.queue.write { db in try record.save(db) }
    }

    func delete(orderID: UUID) async throws {
        let orderID = orderID.uuidString
        try await database.queue.write { db in
            if let bill = try BillLedgerRecord
                .filter(Column("orderID") == orderID)
                .fetchOne(db)
            {
                _ = try PaymentLedgerRecord
                    .filter(Column("billID") == bill.id)
                    .deleteAll(db)
            }
            _ = try BillLedgerRecord.filter(Column("orderID") == orderID).deleteAll(db)
            _ = try OrderPauseLedgerRecord.filter(Column("orderID") == orderID).deleteAll(db)
            _ = try OrderEventLedgerRecord.filter(Column("orderID") == orderID).deleteAll(db)
            _ = try OrderLedgerRecord.filter(Column("id") == orderID).deleteAll(db)
        }
    }

}

private struct BillingScenarioSeed {
    let number: String
    let title: String
    let machineNumber: String
    let machineType: MachineType
    let startedAt: Date
    let endedAt: Date

    static func all() throws -> [BillingScenarioSeed] {
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) throws -> Date {
            guard let value = Calendar.mainlandChina.date(from: DateComponents(
                year: 2026, month: month, day: day, hour: hour, minute: minute
            )) else {
                throw BillingScenarioSeedError.invalidDate
            }
            return value
        }

        return [
            BillingScenarioSeed(number: "01", title: "纯早场", machineNumber: "01", machineType: .fourSeat, startedAt: try date(21, 8, 30), endedAt: try date(21, 12, 30)),
            BillingScenarioSeed(number: "02", title: "日间正常计费，未封顶", machineNumber: "02", machineType: .fourSeat, startedAt: try date(22, 14), endedAt: try date(22, 16)),
            BillingScenarioSeed(number: "03", title: "日间刚好达到封顶", machineNumber: "03", machineType: .fourSeat, startedAt: try date(23, 13), endedAt: try date(23, 17, 48)),
            BillingScenarioSeed(number: "04", title: "日间封顶后继续使用", machineNumber: "05", machineType: .fourSeat, startedAt: try date(24, 13), endedAt: try date(24, 22)),
            BillingScenarioSeed(number: "05", title: "早场跨到日间", machineNumber: "07", machineType: .fourSeat, startedAt: try date(28, 11, 30), endedAt: try date(28, 15)),
            BillingScenarioSeed(number: "06", title: "日间跨到夜场", machineNumber: "09", machineType: .fourSeat, startedAt: try date(21, 20), endedAt: try date(22, 0, 30)),
            BillingScenarioSeed(number: "07", title: "完整跨三时段", machineNumber: "03", machineType: .fourSeat, startedAt: try date(22, 8), endedAt: try date(23, 8)),
            BillingScenarioSeed(number: "08", title: "纯夜场", machineNumber: "06", machineType: .fourSeat, startedAt: try date(23, 23, 30), endedAt: try date(24, 2)),
            BillingScenarioSeed(number: "09", title: "夜场跨到次日早场", machineNumber: "08", machineType: .fourSeat, startedAt: try date(24, 23, 30), endedAt: try date(25, 10)),
            BillingScenarioSeed(number: "10", title: "周末 / 节假日日间封顶", machineNumber: "01", machineType: .fourSeat, startedAt: try date(27, 13), endedAt: try date(27, 22))
        ]
    }
}

private enum BillingScenarioSeedError: Error {
    case invalidDate
}

private struct OrderLedgerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "orderLedger"
    let id: String
    let machineID: String
    let status: String
    let startedAt: Date
    let payload: Data
}

private struct OrderPauseLedgerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "orderPauseLedger"
    let id: String
    let orderID: String
    let payload: Data
}

private struct OrderEventLedgerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "orderEventLedger"
    let id: String
    let orderID: String
    let occurredAt: Date
    let payload: Data
}

private struct BillLedgerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "billLedger"
    let id: String
    let orderID: String
    let payload: Data
}

private struct PaymentLedgerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "paymentLedger"
    let id: String
    let billID: String
    let payload: Data
}

private func deterministicUUID(prefix: String, number: String) -> UUID {
    let scalar = number.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 999_999 }
    let value = String(format: "%06d", scalar)
    return UUID(uuidString: "\(prefix)0000000-0000-0000-0000-000000\(value)") ?? UUID()
}

actor InMemoryOrderRepository: OrderRepository {
    private var orders: [Order] = []
    private var pauses: [OrderPause] = []
    private var events: [OrderEvent] = []
    private var bills: [Bill] = []
    private var payments: [Payment] = []

    func seedIfNeeded(machines: [Machine]) async throws {}
    func fetchOrders() async throws -> [Order] { orders.sorted { $0.startedAt > $1.startedAt } }
    func fetchPauses(orderID: UUID) async throws -> [OrderPause] { pauses.filter { $0.orderID == orderID } }
    func fetchEvents(orderID: UUID) async throws -> [OrderEvent] { events.filter { $0.orderID == orderID }.sorted { $0.occurredAt > $1.occurredAt } }
    func fetchBill(orderID: UUID) async throws -> Bill? { bills.first { $0.orderID == orderID } }
    func fetchPayments(billID: UUID) async throws -> [Payment] { payments.filter { $0.billID == billID } }
    func save(_ order: Order) async throws { upsert(order, in: &orders) }
    func save(_ pause: OrderPause) async throws { upsert(pause, in: &pauses) }
    func save(_ event: OrderEvent) async throws { upsert(event, in: &events) }
    func save(_ bill: Bill) async throws { upsert(bill, in: &bills) }
    func save(_ payment: Payment) async throws { upsert(payment, in: &payments) }
    func delete(orderID: UUID) async throws {
        let billIDs = bills.filter { $0.orderID == orderID }.map(\.id)
        payments.removeAll { billIDs.contains($0.billID) }
        bills.removeAll { $0.orderID == orderID }
        pauses.removeAll { $0.orderID == orderID }
        events.removeAll { $0.orderID == orderID }
        orders.removeAll { $0.id == orderID }
    }

    private func upsert<Value: Identifiable>(_ value: Value, in values: inout [Value]) where Value.ID == UUID {
        if let index = values.firstIndex(where: { $0.id == value.id }) { values[index] = value } else { values.append(value) }
    }
}
