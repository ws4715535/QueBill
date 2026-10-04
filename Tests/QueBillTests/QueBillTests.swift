//
//  QueBillTests.swift
//  QueBillTests
//
//  Created by ws on 2025/10/21.
//

import Foundation
import Testing
@testable import QueBill

struct QueBillTests {
    @Test
    func businessDayUsesOrderStartDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let start = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 27, hour: 23, minute: 40)
        ))
        let end = try #require(calendar.date(byAdding: .hour, value: 3, to: start))

        let businessDay = BusinessDay(orderStartedAt: start, calendar: calendar)

        #expect(calendar.isDate(businessDay.date, inSameDayAs: start))
        #expect(!calendar.isDate(businessDay.date, inSameDayAs: end))
    }

    @Test
    func machineRepositoryPersistsStatusChange() async throws {
        let repository = InMemoryMachineRepository()
        var machines = try await repository.fetchMachines()
        var machine = try #require(machines.first { $0.status == .idle })

        machine.status = .inUse
        machine.openedAt = Date()
        try await repository.save(machine)
        machines = try await repository.fetchMachines()

        let saved = try #require(machines.first { $0.id == machine.id })
        #expect(saved.status == .inUse)
        #expect(saved.openedAt != nil)
    }

    @Test
    func billingExcludesPausedTimeAndStoresRuleSnapshot() throws {
        let startedAt = try mainlandDate(2026, 9, 28, 14, 0, 0)
        let endedAt = startedAt.addingTimeInterval(7_200)
        let order = Order(
            id: UUID(),
            machineID: UUID(),
            machineNumberSnapshot: "07",
            machineTypeSnapshot: .fourSeat,
            status: .active,
            playerCount: 4,
            startedAt: startedAt,
            endedAt: nil,
            businessDay: BusinessDay(orderStartedAt: startedAt, calendar: .mainlandChina),
            note: nil,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let pause = OrderPause(
            id: UUID(),
            orderID: order.id,
            startedAt: startedAt.addingTimeInterval(1_800),
            endedAt: startedAt.addingTimeInterval(5_400)
        )

        let bill = try StandardBillingService().preview(context: BillingContext(
            order: order,
            pauses: [pause],
            pricing: .standard,
            calculatedAt: endedAt
        ))

        #expect(bill.effectiveDuration == 3_600)
        #expect(bill.finalAmount == 40)
        #expect(bill.playerAmounts == [10, 10, 10, 10])
        #expect(!bill.priceRuleSnapshot.isEmpty)
    }

    @Test
    func billingStacksDaytimeNightAndEarlySessionsAcrossMidnight() throws {
        let startedAt = try mainlandDate(2026, 9, 27, 20, 36, 27)
        let endedAt = try mainlandDate(2026, 9, 28, 11, 38, 0)
        let order = Order(
            id: UUID(),
            machineID: UUID(),
            machineNumberSnapshot: "07",
            machineTypeSnapshot: .fourSeat,
            status: .active,
            playerCount: 4,
            startedAt: startedAt,
            endedAt: nil,
            businessDay: BusinessDay(orderStartedAt: startedAt, calendar: .mainlandChina),
            note: nil,
            createdAt: startedAt,
            updatedAt: startedAt
        )

        let bill = try StandardBillingService().preview(context: BillingContext(
            order: order,
            pauses: [],
            pricing: .standard,
            calculatedAt: endedAt
        ))

        #expect(bill.lines.map(\.title) == ["周末 / 节假日日间", "夜场包时", "早场包时"])
        #expect(bill.lines.map(\.amount) == [95.70, 272, 120])
        #expect(bill.finalAmount == 487.70)
        #expect(bill.playerAmounts.map { NSDecimalNumber(decimal: $0 * 100).intValue } == [12193, 12193, 12192, 12192])
    }

    @Test
    func tenCoreBillingScenariosProduceExpectedTotals() throws {
        let cases: [(String, Bill, Decimal)] = [
            ("纯早场", try scenarioBill(21, 8, 30, 21, 12, 30), 120),
            ("日间正常计费", try scenarioBill(22, 14, 0, 22, 16, 0), 80),
            ("日间刚好封顶", try scenarioBill(23, 13, 0, 23, 17, 48), 192),
            ("日间封顶后继续", try scenarioBill(24, 13, 0, 24, 22, 0), 192),
            ("早场跨日间", try scenarioBill(28, 11, 30, 28, 15, 0), 200),
            ("日间跨夜场", try scenarioBill(21, 20, 0, 22, 0, 30), 392),
            ("完整跨三时段", try scenarioBill(22, 8, 0, 23, 8, 0), 584),
            ("纯夜场", try scenarioBill(23, 23, 30, 24, 2, 0), 272),
            ("夜场跨次日早场", try scenarioBill(24, 23, 30, 25, 10, 0), 392),
            ("节假日日间封顶", try scenarioBill(27, 13, 0, 27, 22, 0), 312)
        ]

        for (title, bill, expected) in cases {
            #expect(bill.finalAmount == expected, Comment(rawValue: title))
        }
        #expect(cases[2].1.lines.contains { $0.title.contains("刚好达到封顶") })
        #expect(cases[3].1.lines.contains { $0.title == "日间封顶后继续使用" && $0.amount == 0 })
        #expect(cases[6].1.lines.map(\.title).contains("早场包时"))
        #expect(cases[6].1.lines.map(\.title).contains("夜场包时"))
    }

    @Test
    func crossMidnightOrderKeepsItsStartingBusinessDayCategory() throws {
        let startedAt = try mainlandDate(2026, 9, 18, 22, 0, 0)
        let endedAt = try mainlandDate(2026, 9, 19, 15, 0, 0)
        let order = Order(
            id: UUID(),
            machineID: UUID(),
            machineNumberSnapshot: "X",
            machineTypeSnapshot: .eightSeat,
            status: .active,
            playerCount: 4,
            startedAt: startedAt,
            endedAt: nil,
            businessDay: BusinessDay(orderStartedAt: startedAt, calendar: .mainlandChina),
            note: nil,
            createdAt: startedAt,
            updatedAt: startedAt
        )

        let bill = try StandardBillingService().preview(context: BillingContext(
            order: order,
            pauses: [],
            pricing: .standard,
            calculatedAt: endedAt
        ))

        let nextDayDaytime = try #require(bill.lines.first {
            $0.title == "工作日日间"
                && Calendar.mainlandChina.component(.day, from: $0.startedAt) == 19
        })
        #expect(nextDayDaytime.amount == 120)
        #expect(!bill.lines.contains { $0.title == "周末 / 节假日日间" })
    }

    @Test
    func deletingCompletedOrderRemovesItsFinancialRecords() async throws {
        let repository = InMemoryOrderRepository()
        let startedAt = Date().addingTimeInterval(-3_600)
        let order = Order(
            id: UUID(), machineID: UUID(), machineNumberSnapshot: "01",
            machineTypeSnapshot: .fourSeat, status: .completed, playerCount: 4,
            startedAt: startedAt, endedAt: .now,
            businessDay: BusinessDay(orderStartedAt: startedAt), note: nil,
            createdAt: startedAt, updatedAt: .now
        )
        let bill = Bill(
            id: UUID(), orderID: order.id, startedAt: startedAt, endedAt: .now,
            effectiveDuration: 3_600, lines: [], originalAmount: 40,
            adjustmentAmount: 0, finalAmount: 40, playerAmounts: [10, 10, 10, 10],
            priceRuleSnapshot: Data(), createdAt: .now
        )
        let payment = Payment(
            id: UUID(), billID: bill.id, method: .cash, amount: 40,
            status: .paid, paidAt: .now
        )
        try await repository.save(order)
        try await repository.save(bill)
        try await repository.save(payment)

        try await repository.delete(orderID: order.id)

        #expect(try await repository.fetchOrders().isEmpty)
        #expect(try await repository.fetchBill(orderID: order.id) == nil)
        #expect(try await repository.fetchPayments(billID: bill.id).isEmpty)
    }

    @Test @MainActor
    func openingAndCheckoutCreatesACompletedOrderAndReleasesMachine() async throws {
        let machineRepository = InMemoryMachineRepository()
        let orderRepository = InMemoryOrderRepository()
        let viewModel = MachineDashboardViewModel(
            repository: machineRepository,
            orderRepository: orderRepository
        )
        await viewModel.load()
        let machine = try #require(viewModel.machines.first { $0.status == .idle })

        await viewModel.open(machineID: machine.id)
        let activeOrder = try #require(viewModel.activeOrder(machineID: machine.id))
        #expect(activeOrder.status == .active)

        _ = await viewModel.checkout(
            machineID: machine.id,
            paymentMethods: [.weChat, .weChat, .cash, .memberBalance]
        )

        let completed = try #require(viewModel.orders.first { $0.id == activeOrder.id })
        let snapshot = try #require(viewModel.snapshot(orderID: completed.id))
        #expect(completed.status == .completed)
        #expect(snapshot.bill != nil)
        #expect(snapshot.payments.count == 3)
        #expect(snapshot.payments.allSatisfy { $0.status == .paid })
        #expect(snapshot.paidAmount == snapshot.bill?.finalAmount)
        #expect(viewModel.machine(id: machine.id)?.status == .idle)
    }

    private func mainlandDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int
    ) throws -> Date {
        try #require(Calendar.mainlandChina.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )))
    }

    private func scenarioBill(
        _ startDay: Int,
        _ startHour: Int,
        _ startMinute: Int,
        _ endDay: Int,
        _ endHour: Int,
        _ endMinute: Int
    ) throws -> Bill {
        let start = try mainlandDate(2026, 9, startDay, startHour, startMinute, 0)
        let end = try mainlandDate(2026, 9, endDay, endHour, endMinute, 0)
        let order = Order(
            id: UUID(),
            machineID: UUID(),
            machineNumberSnapshot: "T",
            machineTypeSnapshot: .fourSeat,
            status: .active,
            playerCount: 4,
            startedAt: start,
            endedAt: nil,
            businessDay: BusinessDay(orderStartedAt: start, calendar: .mainlandChina),
            note: nil,
            createdAt: start,
            updatedAt: start
        )
        return try StandardBillingService().preview(context: BillingContext(
            order: order,
            pauses: [],
            pricing: .standard,
            calculatedAt: end
        ))
    }
}
