import Foundation

enum MachineStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case inUse
    case paused
    case maintenance
    case disabled

    var title: String {
        switch self {
        case .idle: "空闲"
        case .inUse: "使用中"
        case .paused: "已暂停"
        case .maintenance: "维护中"
        case .disabled: "已停用"
        }
    }
}

enum MachineType: String, Codable, CaseIterable, Sendable {
    case fourSeat
    case eightSeat

    var title: String {
        switch self {
        case .fourSeat: "四口机"
        case .eightSeat: "八口机"
        }
    }
}

struct Machine: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var number: String
    var type: MachineType
    var status: MachineStatus
    var note: String?
    var openedAt: Date?
    var updatedAt: Date
}

enum OrderStatus: String, Codable, Sendable {
    case active
    case paused
    case pendingPayment
    case completed
    case cancelled
}

struct Order: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let machineID: UUID
    var machineNumberSnapshot: String
    var machineTypeSnapshot: MachineType
    var status: OrderStatus
    var playerCount: Int
    var startedAt: Date
    var endedAt: Date?
    var businessDay: BusinessDay
    var note: String?
    var createdAt: Date
    var updatedAt: Date
}

struct OrderSnapshot: Identifiable, Hashable, Sendable {
    let order: Order
    let pauses: [OrderPause]
    let events: [OrderEvent]
    let bill: Bill?
    let payments: [Payment]

    var id: UUID { order.id }
    var paidAmount: Decimal { payments.reduce(0) { $0 + $1.amount } }
}

struct OrderPause: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let orderID: UUID
    let startedAt: Date
    var endedAt: Date?
}

enum OrderEventKind: String, Codable, Sendable {
    case opened
    case paused
    case resumed
    case startTimeAdjusted
    case checkoutCreated
    case paid
    case cancelled
}

struct OrderEvent: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let orderID: UUID
    let kind: OrderEventKind
    let occurredAt: Date
    let detail: String?
}

struct BusinessDay: Hashable, Codable, Sendable {
    let date: Date

    init(orderStartedAt: Date, calendar: Calendar = .current) {
        date = calendar.startOfDay(for: orderStartedAt)
    }
}

enum DayCategory: String, Codable, Sendable {
    case weekday
    case weekend
    case holiday
}

struct PriceRule: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var machineType: MachineType
    var dayCategory: DayCategory
    var hourlyRatePerPlayer: Decimal
    var daytimeCapPerPlayer: Decimal?
    var earlySessionPricePerPlayer: Decimal?
    var nightSessionPricePerPlayer: Decimal?
    var effectiveFrom: Date
    var updatedAt: Date
}

struct PricingConfiguration: Hashable, Codable, Sendable {
    var earlyStartHour: Int
    var earlyEndHour: Int
    var earlyPricePerPlayer: Decimal
    var nightStartHour: Int
    var nightEndHour: Int
    var nightPricePerPlayer: Decimal
    var weekdayDaytimeCapPerPlayer: Decimal
    var weekendHolidayDaytimeCapPerPlayer: Decimal
    var fourSeatWeekdayRatePerPlayer: Decimal
    var fourSeatWeekendHolidayRatePerPlayer: Decimal
    var eightSeatWeekdayRatePerPlayer: Decimal
    var eightSeatWeekendHolidayRatePerPlayer: Decimal
    var mainlandHolidayDates: Set<String>
    var updatedAt: Date

    static let standard = PricingConfiguration(
        earlyStartHour: 8,
        earlyEndHour: 13,
        earlyPricePerPlayer: 30,
        nightStartHour: 23,
        nightEndHour: 8,
        nightPricePerPlayer: 68,
        weekdayDaytimeCapPerPlayer: 48,
        weekendHolidayDaytimeCapPerPlayer: 78,
        fourSeatWeekdayRatePerPlayer: 10,
        fourSeatWeekendHolidayRatePerPlayer: 10,
        eightSeatWeekdayRatePerPlayer: 15,
        eightSeatWeekendHolidayRatePerPlayer: 20,
        mainlandHolidayDates: MainlandHolidayCalendar.dates2026,
        updatedAt: .now
    )

    func daytimeRate(machineType: MachineType, category: DayCategory) -> Decimal {
        let isSpecialDay = category == .weekend || category == .holiday
        return switch (machineType, isSpecialDay) {
        case (.fourSeat, false): fourSeatWeekdayRatePerPlayer
        case (.fourSeat, true): fourSeatWeekendHolidayRatePerPlayer
        case (.eightSeat, false): eightSeatWeekdayRatePerPlayer
        case (.eightSeat, true): eightSeatWeekendHolidayRatePerPlayer
        }
    }

    func daytimeCap(category: DayCategory) -> Decimal {
        category == .weekday ? weekdayDaytimeCapPerPlayer : weekendHolidayDaytimeCapPerPlayer
    }

    func dayCategory(for date: Date, calendar: Calendar = .mainlandChina) -> DayCategory {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        if mainlandHolidayDates.contains(key) { return .holiday }
        return calendar.isDateInWeekend(date) ? .weekend : .weekday
    }
}

extension Calendar {
    static var mainlandChina: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }
}

enum MainlandHolidayCalendar {
    static let dates2026: Set<String> = {
        let ranges = [
            ("2026-01-01", "2026-01-03"),
            ("2026-02-15", "2026-02-23"),
            ("2026-04-04", "2026-04-06"),
            ("2026-05-01", "2026-05-05"),
            ("2026-06-19", "2026-06-21"),
            ("2026-09-25", "2026-09-27"),
            ("2026-10-01", "2026-10-07")
        ]
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        var dates = Set<String>()
        for (startText, endText) in ranges {
            guard let start = formatter.date(from: startText), let end = formatter.date(from: endText) else { continue }
            var date = start
            while date <= end {
                dates.insert(formatter.string(from: date))
                guard let next = formatter.calendar.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
        }
        return dates
    }()
}

struct BillLine: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date
    let amount: Decimal
}

struct Bill: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let orderID: UUID
    let startedAt: Date
    let endedAt: Date
    let effectiveDuration: TimeInterval
    let lines: [BillLine]
    let originalAmount: Decimal
    let adjustmentAmount: Decimal
    let finalAmount: Decimal
    let playerAmounts: [Decimal]
    let priceRuleSnapshot: Data
    let createdAt: Date
}

enum PaymentMethod: String, Codable, CaseIterable, Sendable {
    case weChat
    case alipay
    case cash
    case memberBalance
}

struct PaymentCollectionConfiguration: Hashable, Codable, Sendable {
    var weChatQRCode: Data?
    var alipayQRCode: Data?
    var updatedAt: Date

    static let empty = PaymentCollectionConfiguration(
        weChatQRCode: nil,
        alipayQRCode: nil,
        updatedAt: .now
    )

    func qrCode(for method: PaymentMethod) -> Data? {
        switch method {
        case .weChat: weChatQRCode
        case .alipay: alipayQRCode
        case .cash, .memberBalance: nil
        }
    }
}

enum PaymentStatus: String, Codable, Sendable {
    case pending
    case paid
    case refunded
    case failed
}

struct Payment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let billID: UUID
    let method: PaymentMethod
    let amount: Decimal
    var status: PaymentStatus
    let paidAt: Date?
}

struct Holiday: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var date: Date
    var isEnabled: Bool
}
