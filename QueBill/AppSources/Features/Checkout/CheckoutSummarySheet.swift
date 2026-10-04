import SwiftUI
import UIKit

struct CheckoutSummarySheet: View {
    @Environment(\.dismiss) private var dismiss

    let machine: Machine
    let bill: Bill
    let paymentConfiguration: PaymentCollectionConfiguration
    let onConfirm: @MainActor ([PaymentMethod], Decimal) async -> OrderSnapshot?
    let onCompleted: @MainActor (OrderSnapshot) -> Void

    @State private var payment: PaymentMethod = .weChat
    @State private var collectionMode: CollectionMode = ProcessInfo.processInfo.arguments.contains("-uiTestingSplitPayment") ? .split : .whole
    @State private var selectedSeats: Set<Int> = []
    @State private var seatAssignments: [Int: PaymentMethod] = [:]
    @State private var lastAssignedMethod: PaymentMethod?
    @State private var adjustmentText = ""
    @State private var isSubmitting = false

    private var adjustment: Decimal {
        Decimal(string: adjustmentText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var finalAmount: Decimal {
        roundedCurrency(max(0, bill.originalAmount + adjustment))
    }

    private var playerAmounts: [Decimal] {
        splitCurrency(finalAmount, count: max(bill.playerAmounts.count, 1))
    }

    private var assignedMethods: [PaymentMethod]? {
        switch collectionMode {
        case .whole:
            return Array(repeating: payment, count: playerAmounts.count)
        case .split:
            let methods = playerAmounts.indices.compactMap { seatAssignments[$0] }
            return methods.count == playerAmounts.count ? methods : nil
        }
    }

    private var remainingAmount: Decimal {
        playerAmounts.indices
            .filter { seatAssignments[$0] == nil }
            .reduce(0) { $0 + playerAmounts[$1] }
    }

    var body: some View {
        NavigationStack {
            checkoutContent
            .navigationTitle("结账收款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var checkoutContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(machine.number)号机")
                        .font(.title2.bold())
                    Text("\(machine.type.productTitle) · 4人")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                BillAmountHero(title: "本桌应收", amount: finalAmount)

                VStack(spacing: 0) {
                    KeyValueRow(title: "开始时间", value: bill.startedAt.formatted(date: .numeric, time: .shortened))
                    Divider()
                    KeyValueRow(title: "结算时间", value: bill.endedAt.formatted(date: .numeric, time: .shortened))
                    Divider()
                    KeyValueRow(title: "总有效时长", value: bill.effectiveDuration.durationText)
                    Divider()
                    KeyValueRow(title: "计费规则", value: "按账单规则快照计算")
                }
                .padding(.horizontal, AppSpacing.medium)
                .productCard()

                BillBreakdownView(
                    bill: bill,
                    machineType: machine.type,
                    playerCount: 4
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("快速分摊")
                            .font(.headline)
                        Spacer()
                        Text("4人")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(playerAmounts.enumerated()), id: \.offset) { index, amount in
                            VStack(spacing: 4) {
                                Text("\(index + 1)号位").font(.caption)
                                Text(amount.currencyText).font(.subheadline.bold()).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(AppColors.backgroundSubtle, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("优惠 / 调整")
                        .font(.headline)
                    HStack {
                        Text("可填写负数作为优惠金额")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        TextField("0.00", text: $adjustmentText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("收款方式")
                        .font(.headline)
                    Picker("收款模式", selection: $collectionMode) {
                        Text("整桌收款").tag(CollectionMode.whole)
                        Text("分开记录").tag(CollectionMode.split)
                    }
                    .pickerStyle(.segmented)

                    if collectionMode == .whole {
                        Picker("收款方式", selection: $payment) {
                            ForEach(PaymentMethod.allCases, id: \.self) { method in
                                Text(method.title).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        splitPaymentEditor
                    }

                    if
                        let qrCodeMethod,
                        let data = paymentConfiguration.qrCode(for: qrCodeMethod),
                        let image = UIImage(data: data)
                    {
                        VStack(spacing: 8) {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(maxWidth: 300, maxHeight: 300)
                            Text("请使用\(qrCodeMethod.title)扫码付款")
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(AppSpacing.medium)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.backgroundSubtle, in: RoundedRectangle(cornerRadius: AppRadius.surface))
                    }
                }

                Button {
                    isSubmitting = true
                    Task {
                        if let assignedMethods, let snapshot = await onConfirm(assignedMethods, adjustment) {
                            onCompleted(snapshot)
                            dismiss()
                        }
                        isSubmitting = false
                    }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else if collectionMode == .split && assignedMethods == nil {
                        Text("仍有 \(remainingAmount.currencyText) 未分配")
                    } else {
                        Text("确认收款 \(finalAmount.currencyText)")
                    }
                }
                .buttonStyle(ProductPrimaryButtonStyle())
                .disabled(isSubmitting || assignedMethods == nil)
            }
            .padding(AppSpacing.xLarge)
        }
    }

    private var qrCodeMethod: PaymentMethod? {
        collectionMode == .whole ? payment : lastAssignedMethod
    }

    private var splitPaymentEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择座位后点击收款渠道")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button("全选") { selectedSeats = Set(playerAmounts.indices) }
                Button("反选") { selectedSeats = Set(playerAmounts.indices).subtracting(selectedSeats) }
                Button("清空") {
                    selectedSeats.removeAll()
                    seatAssignments.removeAll()
                    lastAssignedMethod = nil
                }
            }
            .font(.caption.weight(.medium))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(playerAmounts.indices, id: \.self) { index in
                    Button {
                        if selectedSeats.contains(index) {
                            selectedSeats.remove(index)
                        } else {
                            selectedSeats.insert(index)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(index + 1)号位")
                                    .font(.caption.weight(.medium))
                                Spacer()
                                if selectedSeats.contains(index) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColors.accentStrong)
                                }
                            }
                            Text(playerAmounts[index].currencyText)
                                .font(.subheadline.bold())
                                .monospacedDigit()
                            Text(seatAssignments[index]?.title ?? "未分配")
                                .font(.caption2)
                                .foregroundStyle(seatAssignments[index] == nil ? AppColors.warning : AppColors.accentDefault)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedSeats.contains(index) ? AppColors.accentStrong : AppColors.border, lineWidth: selectedSeats.contains(index) ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    Button {
                        for seat in selectedSeats { seatAssignments[seat] = method }
                        lastAssignedMethod = method
                        selectedSeats.removeAll()
                    } label: {
                        Label(method.title, systemImage: method.symbol)
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedSeats.isEmpty)
                }
            }

            VStack(spacing: 7) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    let amount = playerAmounts.indices
                        .filter { seatAssignments[$0] == method }
                        .reduce(0) { $0 + playerAmounts[$1] }
                    if amount > 0 {
                        HStack {
                            Text(method.title)
                            Spacer()
                            Text(amount.currencyText).monospacedDigit()
                        }
                    }
                }
                Divider()
                HStack {
                    Text("待分配")
                    Spacer()
                    Text(remainingAmount.currencyText)
                        .foregroundStyle(remainingAmount == 0 ? AppColors.accentDefault : AppColors.warning)
                        .monospacedDigit()
                }
            }
            .font(.caption.weight(.medium))
        }
    }

    private func roundedCurrency(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .bankers)
        return result
    }

    private func splitCurrency(_ amount: Decimal, count: Int) -> [Decimal] {
        let cents = NSDecimalNumber(decimal: amount * 100).intValue
        let base = cents / count
        let remainder = cents % count
        return (0..<count).map { Decimal(base + ($0 < remainder ? 1 : 0)) / 100 }
    }
}

private enum CollectionMode: Hashable {
    case whole
    case split
}

private struct BillAmountHero: View {
    let title: String
    let amount: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Text(amount.currencyText)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.065), in: RoundedRectangle(cornerRadius: AppRadius.hero))
    }
}

struct BillBreakdownView: View {
    let bill: Bill
    let machineType: MachineType
    let playerCount: Int

    private var pricing: PricingConfiguration? {
        try? JSONDecoder().decode(PricingConfiguration.self, from: bill.priceRuleSnapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("计费明细")
                .font(.headline)
                .padding(.bottom, 8)

            ForEach(bill.lines) { line in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.title).font(.subheadline.weight(.semibold))
                        Text(periodText(for: line))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(formulaText(for: line))
                            .font(.caption)
                            .foregroundStyle(line.amount == 0 ? AppColors.accentDefault : AppColors.textSecondary)
                    }
                    Spacer()
                    Text(line.amount.currencyText)
                        .font(.subheadline.bold())
                        .monospacedDigit()
                }
                .padding(.vertical, 12)
                if line.id != bill.lines.last?.id { Divider() }
            }

            Divider()
            KeyValueRow(title: "有效时长", value: bill.effectiveDuration.durationText)
            Divider()
            KeyValueRow(title: "本桌合计", value: bill.originalAmount.currencyText)
        }
        .padding(AppSpacing.medium)
        .productCard()
    }

    private func periodText(for line: BillLine) -> String {
        let sameDay = Calendar.mainlandChina.isDate(line.startedAt, inSameDayAs: line.endedAt)
        let start = line.startedAt.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
        let end = line.endedAt.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
        return "\(start)–\(end)"
    }

    private func formulaText(for line: BillLine) -> String {
        guard let pricing else { return "已按结账时保存的规则计算" }
        if line.amount == 0 { return "已达到日间封顶，本时段不再增加费用" }
        if line.title.contains("早场") {
            return "\(pricing.earlyPricePerPlayer.currencyText) / 人 × \(playerCount)人"
        }
        if line.title.contains("夜场") {
            return "\(pricing.nightPricePerPlayer.currencyText) / 人 × \(playerCount)人"
        }
        let category = pricing.dayCategory(for: bill.startedAt)
        let cap = pricing.daytimeCap(category: category)
        if line.title.contains("封顶") || line.amount == cap * Decimal(playerCount) {
            return "\(cap.currencyText) / 人封顶 × \(playerCount)人"
        }
        let rate = pricing.daytimeRate(machineType: machineType, category: category)
        return "\(rate.currencyText) / 人·小时 × \(playerCount)人，按有效时长计费"
    }
}

extension Decimal {
    var currencyText: String {
        formatted(.currency(code: "CNY").precision(.fractionLength(2)))
    }
}

extension TimeInterval {
    var durationText: String {
        let value = max(0, Int(self))
        return String(format: "%02d:%02d:%02d", value / 3_600, (value % 3_600) / 60, value % 60)
    }
}

extension PaymentMethod {
    var title: String {
        switch self {
        case .weChat: "微信"
        case .alipay: "支付宝"
        case .cash: "现金"
        case .memberBalance: "会员余额"
        }
    }

    var symbol: String {
        switch self {
        case .weChat: "message.fill"
        case .alipay: "a.circle.fill"
        case .cash: "banknote.fill"
        case .memberBalance: "person.crop.circle.badge.checkmark"
        }
    }
}
