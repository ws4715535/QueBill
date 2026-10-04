import Foundation
import Observation
import OSLog

enum MachineDashboardFilter: String, CaseIterable, Identifiable {
    case all
    case available
    case running
    case attention

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部"
        case .available: "空闲"
        case .running: "使用中"
        case .attention: "需处理"
        }
    }
}

@MainActor
@Observable
final class MachineDashboardViewModel {
    private static let logger = Logger(subsystem: "ws.QueBill", category: "MachineDashboard")
    private let repository: any MachineRepository
    private let orderRepository: any OrderRepository
    private let pricingRepository: any PricingConfigurationRepository
    private let paymentConfigurationRepository: any PaymentCollectionConfigurationRepository
    private let billingService: any BillingService

    private(set) var machines: [Machine] = []
    private(set) var orders: [Order] = []
    private(set) var billsByOrderID: [UUID: Bill] = [:]
    private(set) var paymentsByBillID: [UUID: [Payment]] = [:]
    private(set) var eventsByOrderID: [UUID: [OrderEvent]] = [:]
    private(set) var pausesByOrderID: [UUID: [OrderPause]] = [:]
    private(set) var pricingConfiguration: PricingConfiguration = .standard
    private(set) var paymentConfiguration: PaymentCollectionConfiguration = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var notice: AppNotice?

    var filteredMachines: [Machine] {
        switch filter {
        case .all:
            machines
        case .available:
            machines.filter { $0.status == .idle }
        case .running:
            machines.filter { $0.status == .inUse || $0.status == .paused }
        case .attention:
            machines.filter { $0.status == .maintenance || $0.status == .disabled }
        }
    }

    var filter: MachineDashboardFilter = .all

    init(
        repository: any MachineRepository,
        orderRepository: any OrderRepository = InMemoryOrderRepository(),
        pricingRepository: any PricingConfigurationRepository = InMemoryPricingConfigurationRepository(),
        paymentConfigurationRepository: any PaymentCollectionConfigurationRepository = InMemoryPaymentCollectionConfigurationRepository(),
        billingService: any BillingService = StandardBillingService()
    ) {
        self.repository = repository
        self.orderRepository = orderRepository
        self.pricingRepository = pricingRepository
        self.paymentConfigurationRepository = paymentConfigurationRepository
        self.billingService = billingService
    }

    var availableCount: Int {
        machines.count { $0.status == .idle }
    }

    var activeCount: Int {
        machines.count { $0.status == .inUse || $0.status == .paused }
    }

    var attentionCount: Int {
        machines.count { $0.status == .maintenance || $0.status == .disabled }
    }

    func machine(id: UUID) -> Machine? {
        machines.first { $0.id == id }
    }

    func load() async {
        guard machines.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await repository.seedIfNeeded()
            machines = try await repository.fetchMachines()
            pricingConfiguration = try await pricingRepository.fetch()
            paymentConfiguration = try await paymentConfigurationRepository.fetch()
            try await orderRepository.seedIfNeeded(machines: machines)
            try await reloadOrders()
        } catch {
            Self.logger.error("Initial data load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "暂时无法读取机器数据"
        }
    }

    func reload() async {
        do {
            machines = try await repository.fetchMachines()
            pricingConfiguration = try await pricingRepository.fetch()
            paymentConfiguration = try await paymentConfigurationRepository.fetch()
            try await reloadOrders()
            errorMessage = nil
        } catch {
            errorMessage = "刷新失败，请稍后再试"
        }
    }

    func open(machineID: UUID) async {
        guard let machine = machine(id: machineID), machine.status == .idle else { return }
        let now = Date()
        let order = Order(
            id: UUID(),
            machineID: machine.id,
            machineNumberSnapshot: machine.number,
            machineTypeSnapshot: machine.type,
            status: .active,
            playerCount: 4,
            startedAt: now,
            endedAt: nil,
            businessDay: BusinessDay(orderStartedAt: now),
            note: nil,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await orderRepository.save(order)
            try await orderRepository.save(OrderEvent(
                id: UUID(), orderID: order.id, kind: .opened,
                occurredAt: now, detail: "前台确认开台"
            ))
            await update(machineID: machineID, status: .inUse, openedAt: now, message: "已开始计时")
            try await reloadOrders()
        } catch {
            notice = AppNotice(message: "开台失败，请重试", isError: true)
        }
    }

    func pause(machineID: UUID) async {
        guard var order = activeOrder(machineID: machineID) else { return }
        let now = Date()
        order.status = .paused
        order.updatedAt = now
        do {
            try await orderRepository.save(order)
            try await orderRepository.save(OrderPause(id: UUID(), orderID: order.id, startedAt: now, endedAt: nil))
            try await orderRepository.save(OrderEvent(id: UUID(), orderID: order.id, kind: .paused, occurredAt: now, detail: "前台暂停计费"))
            await update(machineID: machineID, status: .paused, message: "计时已暂停")
            try await reloadOrders()
        } catch {
            notice = AppNotice(message: "暂停失败，请重试", isError: true)
        }
    }

    func resume(machineID: UUID) async {
        guard var order = activeOrder(machineID: machineID) else { return }
        let now = Date()
        order.status = .active
        order.updatedAt = now
        do {
            if var pause = pausesByOrderID[order.id]?.first(where: { $0.endedAt == nil }) {
                pause.endedAt = now
                try await orderRepository.save(pause)
            }
            try await orderRepository.save(order)
            try await orderRepository.save(OrderEvent(id: UUID(), orderID: order.id, kind: .resumed, occurredAt: now, detail: "恢复计费"))
            await update(machineID: machineID, status: .inUse, message: "已继续计时")
            try await reloadOrders()
        } catch {
            notice = AppNotice(message: "恢复失败，请重试", isError: true)
        }
    }

    func checkout(
        machineID: UUID,
        paymentMethod: PaymentMethod,
        adjustment: Decimal = 0
    ) async -> OrderSnapshot? {
        guard let order = activeOrder(machineID: machineID) else { return nil }
        return await checkout(
            machineID: machineID,
            paymentMethods: Array(repeating: paymentMethod, count: order.playerCount),
            adjustment: adjustment
        )
    }

    func checkout(
        machineID: UUID,
        paymentMethods: [PaymentMethod],
        adjustment: Decimal = 0
    ) async -> OrderSnapshot? {
        guard var order = activeOrder(machineID: machineID) else { return nil }
        guard paymentMethods.count == order.playerCount else {
            notice = AppNotice(message: "请为每个座位选择收款渠道", isError: true)
            return nil
        }
        let now = Date()
        do {
            var bill = try billingService.preview(context: BillingContext(
                order: order,
                pauses: pausesByOrderID[order.id] ?? [],
                pricing: pricingConfiguration,
                calculatedAt: now
            ))
            let finalAmount = roundedCurrency(max(0, bill.originalAmount + adjustment))
            bill = Bill(
                id: bill.id, orderID: bill.orderID, startedAt: bill.startedAt, endedAt: bill.endedAt,
                effectiveDuration: bill.effectiveDuration, lines: bill.lines,
                originalAmount: bill.originalAmount, adjustmentAmount: adjustment,
                finalAmount: finalAmount,
                playerAmounts: splitCurrency(finalAmount, count: order.playerCount),
                priceRuleSnapshot: bill.priceRuleSnapshot, createdAt: bill.createdAt
            )
            let groupedAmounts = zip(paymentMethods, bill.playerAmounts).reduce(into: [PaymentMethod: Decimal]()) {
                $0[$1.0, default: 0] += $1.1
            }
            let payments = groupedAmounts.map { method, amount in
                Payment(
                    id: UUID(), billID: bill.id, method: method,
                    amount: amount, status: .paid, paidAt: now
                )
            }
            order.status = .completed
            order.endedAt = now
            order.updatedAt = now
            try await orderRepository.save(bill)
            try await orderRepository.save(OrderEvent(
                id: UUID(), orderID: order.id, kind: .checkoutCreated,
                occurredAt: now, detail: "生成最终账单 \(finalAmount.currencyText)"
            ))
            for payment in payments {
                try await orderRepository.save(payment)
            }
            try await orderRepository.save(order)
            let channelSummary = payments
                .sorted { $0.method.rawValue < $1.method.rawValue }
                .map { "\($0.method.title) \($0.amount.currencyText)" }
                .joined(separator: "、")
            try await orderRepository.save(OrderEvent(
                id: UUID(), orderID: order.id, kind: .paid,
                occurredAt: now, detail: channelSummary
            ))
            await update(machineID: machineID, status: .idle, openedAt: nil, message: "已完成结账")
            try await reloadOrders()
            notice = AppNotice(message: "结账成功，最终账单已保存", isError: false)
            return snapshot(orderID: order.id)
        } catch {
            notice = AppNotice(message: "结账没有完成，请重试", isError: true)
            return nil
        }
    }

    func savePricingConfiguration(_ configuration: PricingConfiguration) async -> Bool {
        guard
            configuration.earlyStartHour < configuration.earlyEndHour,
            configuration.earlyEndHour <= configuration.nightStartHour,
            configuration.nightEndHour <= configuration.earlyStartHour
        else {
            notice = AppNotice(message: "早场、日间和夜场时间不能重叠", isError: true)
            return false
        }
        let prices = [
            configuration.earlyPricePerPlayer,
            configuration.nightPricePerPlayer,
            configuration.weekdayDaytimeCapPerPlayer,
            configuration.weekendHolidayDaytimeCapPerPlayer,
            configuration.fourSeatWeekdayRatePerPlayer,
            configuration.fourSeatWeekendHolidayRatePerPlayer,
            configuration.eightSeatWeekdayRatePerPlayer,
            configuration.eightSeatWeekendHolidayRatePerPlayer
        ]
        guard prices.allSatisfy({ $0 >= 0 }) else {
            notice = AppNotice(message: "价格不能小于 0", isError: true)
            return false
        }
        var updated = configuration
        updated.updatedAt = .now
        do {
            try await pricingRepository.save(updated)
            pricingConfiguration = updated
            notice = AppNotice(message: "价格规则已保存", isError: false)
            return true
        } catch {
            notice = AppNotice(message: "价格规则保存失败", isError: true)
            return false
        }
    }

    func savePaymentQRCode(_ data: Data?, for method: PaymentMethod) async {
        guard method == .weChat || method == .alipay else { return }
        var updated = paymentConfiguration
        switch method {
        case .weChat:
            updated.weChatQRCode = data
        case .alipay:
            updated.alipayQRCode = data
        case .cash, .memberBalance:
            return
        }
        updated.updatedAt = .now
        do {
            try await paymentConfigurationRepository.save(updated)
            paymentConfiguration = updated
            notice = AppNotice(
                message: data == nil ? "\(method.title)收款码已删除" : "\(method.title)收款码已保存",
                isError: false
            )
        } catch {
            notice = AppNotice(message: "收款码保存失败，请重试", isError: true)
        }
    }

    func markMaintenance(machineID: UUID) async {
        await update(machineID: machineID, status: .maintenance, message: "已转为维护中")
    }

    func saveMachine(
        machineID: UUID,
        number: String,
        type: MachineType,
        status: MachineStatus,
        note: String
    ) async {
        guard var machine = machine(id: machineID) else { return }
        guard machine.status != .inUse && machine.status != .paused else {
            notice = AppNotice(message: "计费中的机器不能修改档案", isError: true)
            return
        }
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else {
            notice = AppNotice(message: "机器编号不能为空", isError: true)
            return
        }
        machine.number = normalizedNumber
        machine.type = type
        machine.status = status
        machine.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        machine.updatedAt = .now
        do {
            try await repository.save(machine)
            await reload()
            notice = AppNotice(message: "机器档案已保存", isError: false)
        } catch {
            notice = AppNotice(message: "机器档案保存失败", isError: true)
        }
    }

    func createMachine(
        number: String,
        type: MachineType,
        status: MachineStatus,
        note: String
    ) async {
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else {
            notice = AppNotice(message: "机器编号不能为空", isError: true)
            return
        }
        guard !machines.contains(where: { $0.number.caseInsensitiveCompare(normalizedNumber) == .orderedSame }) else {
            notice = AppNotice(message: "机器编号已存在", isError: true)
            return
        }
        let machine = Machine(
            id: UUID(),
            number: normalizedNumber,
            type: type,
            status: status,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
            openedAt: nil,
            updatedAt: .now
        )
        do {
            try await repository.save(machine)
            await reload()
            notice = AppNotice(message: "\(normalizedNumber)号机已添加", isError: false)
        } catch {
            notice = AppNotice(message: "机器添加失败，请重试", isError: true)
        }
    }

    func deleteMachine(machineID: UUID) async {
        guard let machine = machine(id: machineID) else { return }
        guard machine.status != .inUse && machine.status != .paused else {
            notice = AppNotice(message: "计费中的机器不能删除，请先结账", isError: true)
            return
        }
        do {
            try await repository.delete(machineID: machineID)
            await reload()
            notice = AppNotice(message: "\(machine.number)号机已删除", isError: false)
        } catch {
            notice = AppNotice(message: "机器删除失败，请重试", isError: true)
        }
    }

    func deleteOrder(orderID: UUID) async {
        guard let order = orders.first(where: { $0.id == orderID }) else { return }
        guard order.status == .completed || order.status == .cancelled else {
            notice = AppNotice(message: "进行中的订单不能删除", isError: true)
            return
        }
        do {
            try await orderRepository.delete(orderID: orderID)
            try await reloadOrders()
            notice = AppNotice(message: "订单已删除，运营数据已重新计算", isError: false)
        } catch {
            notice = AppNotice(message: "订单删除失败，请重试", isError: true)
        }
    }

    func restore(machineID: UUID) async {
        await update(machineID: machineID, status: .idle, openedAt: nil, message: "已恢复为空闲")
    }

    func updateNote(machineID: UUID, note: String) async {
        guard var machine = machine(id: machineID) else { return }
        machine.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        machine.updatedAt = Date()

        do {
            try await repository.save(machine)
            if let index = machines.firstIndex(where: { $0.id == machineID }) {
                machines[index] = machine
            }
            if var order = activeOrder(machineID: machineID) {
                order.note = machine.note
                order.updatedAt = Date()
                try await orderRepository.save(order)
                try await reloadOrders()
            }
            notice = AppNotice(message: "\(machine.number)号机 备注已更新", isError: false)
        } catch {
            notice = AppNotice(message: "备注没有保存，请重试", isError: true)
        }
    }

    func adjustOpenedAt(machineID: UUID, to date: Date) async {
        guard date <= Date(), var machine = machine(id: machineID) else {
            notice = AppNotice(message: "开台时间不能晚于当前时间", isError: true)
            return
        }

        machine.openedAt = date
        machine.updatedAt = Date()

        do {
            try await repository.save(machine)
            if let index = machines.firstIndex(where: { $0.id == machineID }) {
                machines[index] = machine
            }
            if var order = activeOrder(machineID: machineID) {
                let previous = order.startedAt
                order.startedAt = date
                order.businessDay = BusinessDay(orderStartedAt: date)
                order.updatedAt = Date()
                try await orderRepository.save(order)
                try await orderRepository.save(OrderEvent(
                    id: UUID(), orderID: order.id, kind: .startTimeAdjusted,
                    occurredAt: .now,
                    detail: "从 \(previous.formatted(date: .omitted, time: .shortened)) 调整为 \(date.formatted(date: .omitted, time: .shortened))"
                ))
                try await reloadOrders()
            }
            notice = AppNotice(message: "\(machine.number)号机 开台时间已更新", isError: false)
        } catch {
            notice = AppNotice(message: "开台时间没有保存，请重试", isError: true)
        }
    }

    func clearNotice() {
        notice = nil
    }

    func activeOrder(machineID: UUID) -> Order? {
        orders.first { $0.machineID == machineID && ($0.status == .active || $0.status == .paused) }
    }

    func snapshot(orderID: UUID) -> OrderSnapshot? {
        guard let order = orders.first(where: { $0.id == orderID }) else { return nil }
        let bill = billsByOrderID[orderID]
        return OrderSnapshot(
            order: order,
            pauses: pausesByOrderID[orderID] ?? [],
            events: eventsByOrderID[orderID] ?? [],
            bill: bill,
            payments: bill.flatMap { paymentsByBillID[$0.id] } ?? []
        )
    }

    func previewBill(machineID: UUID, at date: Date = .now) -> Bill? {
        guard let order = activeOrder(machineID: machineID) else { return nil }
        return try? billingService.preview(context: BillingContext(
            order: order,
            pauses: pausesByOrderID[order.id] ?? [],
            pricing: pricingConfiguration,
            calculatedAt: date
        ))
    }

    private func reloadOrders() async throws {
        let loadedOrders = try await orderRepository.fetchOrders()
        var loadedBills: [UUID: Bill] = [:]
        var loadedPayments: [UUID: [Payment]] = [:]
        var loadedEvents: [UUID: [OrderEvent]] = [:]
        var loadedPauses: [UUID: [OrderPause]] = [:]
        for order in loadedOrders {
            loadedEvents[order.id] = (try? await orderRepository.fetchEvents(orderID: order.id)) ?? []
            loadedPauses[order.id] = (try? await orderRepository.fetchPauses(orderID: order.id)) ?? []
            if let bill = try? await orderRepository.fetchBill(orderID: order.id) {
                loadedBills[order.id] = bill
                loadedPayments[bill.id] = (try? await orderRepository.fetchPayments(billID: bill.id)) ?? []
            }
        }
        orders = loadedOrders
        billsByOrderID = loadedBills
        paymentsByBillID = loadedPayments
        eventsByOrderID = loadedEvents
        pausesByOrderID = loadedPauses
    }

    private func splitCurrency(_ amount: Decimal, count: Int) -> [Decimal] {
        guard count > 0 else { return [] }
        let cents = NSDecimalNumber(decimal: amount * 100).intValue
        let base = cents / count
        let remainder = cents % count
        return (0..<count).map { Decimal(base + ($0 < remainder ? 1 : 0)) / 100 }
    }

    private func roundedCurrency(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .bankers)
        return result
    }

    private func update(
        machineID: UUID,
        status: MachineStatus,
        openedAt: Date? = nil,
        message: String
    ) async {
        guard var machine = machine(id: machineID) else { return }
        machine.status = status
        if status == .idle || status == .maintenance || status == .disabled || openedAt != nil {
            machine.openedAt = openedAt
        }
        machine.updatedAt = Date()

        do {
            try await repository.save(machine)
            if let index = machines.firstIndex(where: { $0.id == machineID }) {
                machines[index] = machine
            }
            notice = AppNotice(message: "\(machine.number)号机 \(message)", isError: false)
        } catch {
            notice = AppNotice(message: "操作没有保存，请重试", isError: true)
        }
    }
}
