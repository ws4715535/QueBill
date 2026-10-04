import Foundation

extension MachineType {
    var productTitle: String {
        switch self {
        case .fourSeat: "大洋化学四口机"
        case .eightSeat: "大洋化学八口机（包间）"
        }
    }

    var weekdayRateText: String {
        switch self {
        case .fourSeat: "¥10 / 人·小时"
        case .eightSeat: "¥20 / 人·小时"
        }
    }

    var daytimeCapText: String {
        switch self {
        case .fourSeat: "¥48 / 人"
        case .eightSeat: "¥78 / 人"
        }
    }
}

extension Machine {
    var orderCode: String { "DEMO-\(number)" }

    var currentAmount: Decimal {
        switch number {
        case "02": 58.36
        case "03": 312.00
        case "07": 32.85
        case "09": 217.05
        default: 0
        }
    }

    var displayAmount: String {
        currentAmount.formatted(.currency(code: "CNY"))
    }

    var effectiveNote: String {
        guard let note, !note.isEmpty else { return "预置营业演示" }
        return note
    }
}

extension Order {
    var displayCode: String {
        if note?.contains("演示") == true {
            return "DEMO-\(machineNumberSnapshot)"
        }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: businessDay.date)
        let datePart = String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let suffix = id.uuidString.replacingOccurrences(of: "-", with: "").suffix(6)
        return "QB-\(datePart)-\(suffix)"
    }
}

extension OrderEventKind {
    var title: String {
        switch self {
        case .opened: "开台"
        case .paused: "暂停计费"
        case .resumed: "恢复计费"
        case .startTimeAdjusted: "调整开台时间"
        case .checkoutCreated: "生成账单"
        case .paid: "完成收款"
        case .cancelled: "取消订单"
        }
    }

    var symbol: String {
        switch self {
        case .opened, .resumed: "play.fill"
        case .paused: "pause.fill"
        case .startTimeAdjusted: "clock.arrow.circlepath"
        case .checkoutCreated: "doc.text"
        case .paid: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}
