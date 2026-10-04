import SwiftUI

private enum OrderListFilter: String, CaseIterable, Identifiable {
    case active
    case today
    case history

    var id: Self { self }
    var title: String {
        switch self {
        case .active: "进行中"
        case .today: "今日"
        case .history: "历史"
        }
    }
}

struct OrdersView: View {
    let viewModel: MachineDashboardViewModel

    @State private var filter: OrderListFilter
    @State private var query = ""
    @State private var selectedOrderID: UUID?
    @State private var orderPendingDeletion: OrderSnapshot?

    init(viewModel: MachineDashboardViewModel) {
        self.viewModel = viewModel
        _filter = State(initialValue: ProcessInfo.processInfo.arguments.contains("-uiTestingHistory") ? .history : .active)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProductScreenHeader("订单", subtitle: "订单记录与结算账单")

            GeometryReader { proxy in
                if proxy.size.width >= 850 {
                    HStack(alignment: .top, spacing: AppSpacing.large) {
                        orderList(usesNavigationLinks: false)
                            .frame(width: min(430, proxy.size.width * 0.38))
                        selectedDetail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(AppSpacing.xLarge)
                } else {
                    orderList(usesNavigationLinks: true)
                        .padding(AppSpacing.medium)
                }
            }
        }
        .background(AppColors.backgroundPrimary)
        .task {
            await viewModel.load()
            selectFirstVisibleOrder()
        }
        .onChange(of: filter) { _, _ in selectFirstVisibleOrder() }
        .onChange(of: viewModel.orders) { _, _ in selectFirstVisibleOrder() }
        .alert(
            "删除这笔订单？",
            isPresented: Binding(
                get: { orderPendingDeletion != nil },
                set: { if !$0 { orderPendingDeletion = nil } }
            ),
            presenting: orderPendingDeletion
        ) { snapshot in
            Button("取消", role: .cancel) {}
            Button("删除订单", role: .destructive) {
                Task { await viewModel.deleteOrder(orderID: snapshot.id) }
            }
        } message: { snapshot in
            Text("订单 \(snapshot.order.displayCode) 的账单与支付记录将一并删除，运营报表会立即重新计算。")
        }
    }

    private func orderList(usesNavigationLinks: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Picker("订单范围", selection: $filter) {
                ForEach(OrderListFilter.allCases) { item in
                    Text("\(item.title) \(count(for: item))").tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: AppSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textSecondary)
                TextField("订单号或机器号", text: $query)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .productCard(radius: 10)

            HStack {
                Text("订单列表")
                    .font(AppTypography.sectionTitle)
                Spacer()
                Text("共 \(visibleSnapshots.count) 笔")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if visibleSnapshots.isEmpty {
                        ContentUnavailableView(
                            "没有符合条件的订单",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(visibleSnapshots) { snapshot in
                            orderRow(snapshot, usesNavigationLink: usesNavigationLinks)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func orderRow(_ snapshot: OrderSnapshot, usesNavigationLink: Bool) -> some View {
        HStack(spacing: AppSpacing.small) {
            if usesNavigationLink {
                NavigationLink {
                    OrderDetailView(snapshot: snapshot)
                } label: {
                    OrderListCard(snapshot: snapshot, isSelected: false)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    selectedOrderID = snapshot.id
                } label: {
                    OrderListCard(snapshot: snapshot, isSelected: selectedOrderID == snapshot.id)
                }
                .buttonStyle(.plain)
            }

            if canDelete(snapshot) {
                Button {
                    orderPendingDeletion = snapshot
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.danger)
                .accessibilityLabel("删除订单 \(snapshot.order.displayCode)")
            }
        }
    }

    private func canDelete(_ snapshot: OrderSnapshot) -> Bool {
        snapshot.order.status == .completed || snapshot.order.status == .cancelled
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let selectedSnapshot {
            OrderDetailView(snapshot: selectedSnapshot, embedded: true)
                .productCard(radius: 14)
        } else {
            ContentUnavailableView(
                "选择一笔订单",
                systemImage: "doc.text",
                description: Text("订单详情与最终账单会显示在这里。")
            )
            .productCard(radius: 14)
        }
    }

    private var allSnapshots: [OrderSnapshot] {
        viewModel.orders.compactMap { viewModel.snapshot(orderID: $0.id) }
    }

    private var visibleSnapshots: [OrderSnapshot] {
        allSnapshots.filter { snapshot in
            let statusMatches: Bool
            switch filter {
            case .active:
                statusMatches = snapshot.order.status == .active || snapshot.order.status == .paused
            case .today:
                statusMatches = Calendar.current.isDateInToday(snapshot.order.endedAt ?? snapshot.order.startedAt)
            case .history:
                statusMatches = snapshot.order.status == .completed || snapshot.order.status == .cancelled
            }
            guard statusMatches else { return false }
            guard !query.isEmpty else { return true }
            return snapshot.order.displayCode.localizedCaseInsensitiveContains(query)
                || snapshot.order.machineNumberSnapshot.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedSnapshot: OrderSnapshot? {
        guard let selectedOrderID else { return visibleSnapshots.first }
        return visibleSnapshots.first { $0.id == selectedOrderID }
    }

    private func count(for filter: OrderListFilter) -> Int {
        switch filter {
        case .active:
            allSnapshots.count { $0.order.status == .active || $0.order.status == .paused }
        case .today:
            allSnapshots.count { Calendar.current.isDateInToday($0.order.endedAt ?? $0.order.startedAt) }
        case .history:
            allSnapshots.count { $0.order.status == .completed || $0.order.status == .cancelled }
        }
    }

    private func selectFirstVisibleOrder() {
        if let selectedOrderID, visibleSnapshots.contains(where: { $0.id == selectedOrderID }) { return }
        selectedOrderID = visibleSnapshots.first?.id
    }
}

private struct OrderListCard: View {
    let snapshot: OrderSnapshot
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(snapshot.order.displayCode)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                StatusPill(title: snapshot.order.status.title, isActive: snapshot.order.status == .active)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if let note = snapshot.order.note, note.hasPrefix("计费场景") {
                        Text(note)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.accentDefault)
                            .lineLimit(1)
                    } else {
                        Text("\(snapshot.order.machineNumberSnapshot)号机 · \(snapshot.order.playerCount)人")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Text(snapshot.order.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text(snapshot.bill?.finalAmount.currencyText ?? "计费中")
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.accentStrong)
                    .monospacedDigit()
            }
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 108)
        .productCard(
            borderColor: isSelected ? AppColors.accentDefault : AppColors.border,
            background: isSelected ? AppColors.accentSubtle : AppColors.surface
        )
    }
}

struct OrderDetailView: View {
    let snapshot: OrderSnapshot
    var embedded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(snapshot.order.machineNumberSnapshot)号机")
                            .font(.title2.bold())
                        Text(snapshot.order.machineTypeSnapshot.productTitle)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    StatusPill(title: snapshot.order.status.title, isActive: snapshot.order.status == .active)
                }

                if let bill = snapshot.bill {
                    billHero(bill)
                    BillBreakdownView(
                        bill: bill,
                        machineType: snapshot.order.machineTypeSnapshot,
                        playerCount: snapshot.order.playerCount
                    )
                    billDetails(bill)
                } else {
                    activeOrderHero
                }

                VStack(spacing: 0) {
                    KeyValueRow(title: "订单号", value: snapshot.order.displayCode)
                    Divider()
                    KeyValueRow(title: "开台时间", value: snapshot.order.startedAt.formatted(date: .numeric, time: .shortened))
                    Divider()
                    KeyValueRow(title: "结束时间", value: snapshot.order.endedAt?.formatted(date: .numeric, time: .shortened) ?? "进行中")
                    Divider()
                    KeyValueRow(title: "营业日", value: snapshot.order.businessDay.date.formatted(date: .numeric, time: .omitted))
                    Divider()
                    KeyValueRow(title: "备注", value: snapshot.order.note ?? "无")
                }
                .padding(.horizontal, AppSpacing.medium)
                .productCard()

                if !snapshot.events.isEmpty {
                    Text("订单事件")
                        .font(AppTypography.sectionTitle)
                    ForEach(snapshot.events) { event in
                        HStack {
                            Text(event.kind.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(event.occurredAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(embedded ? 28 : AppSpacing.large)
        }
        .background(embedded ? AppColors.surface : AppColors.backgroundPrimary)
        .navigationTitle("订单详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activeOrderHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前状态")
                .font(.caption)
                .foregroundStyle(AppColors.accentSubtle)
            Text(snapshot.order.status == .paused ? "计费已暂停" : "正在计费")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Text("机器操作请前往机器详情")
                .font(.caption)
                .foregroundStyle(AppColors.accentSubtle)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentStrong, in: RoundedRectangle(cornerRadius: AppRadius.hero))
    }

    private func billHero(_ bill: Bill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最终实收")
                .font(.caption)
                .foregroundStyle(AppColors.accentSubtle)
            Text(bill.finalAmount.currencyText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(paymentSummary)
                .font(.caption)
                .foregroundStyle(AppColors.accentSubtle)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentStrong, in: RoundedRectangle(cornerRadius: AppRadius.hero))
    }

    private var paymentSummary: String {
        guard !snapshot.payments.isEmpty else { return "待支付" }
        return snapshot.payments
            .sorted { $0.method.rawValue < $1.method.rawValue }
            .map { "\($0.method.title) \($0.amount.currencyText)" }
            .joined(separator: " · ")
    }

    private func billDetails(_ bill: Bill) -> some View {
        VStack(spacing: 0) {
            KeyValueRow(title: "总时长", value: bill.effectiveDuration.durationText)
            Divider()
            KeyValueRow(title: "一桌总价", value: bill.originalAmount.currencyText)
            Divider()
            KeyValueRow(title: "优惠 / 调整", value: bill.adjustmentAmount.currencyText)
            Divider()
            KeyValueRow(title: "最终应收", value: bill.finalAmount.currencyText)
            Divider()
            ForEach(Array(bill.playerAmounts.enumerated()), id: \.offset) { index, amount in
                KeyValueRow(title: "玩家 \(index + 1)", value: amount.currencyText)
                if index < bill.playerAmounts.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .productCard()
    }
}

extension OrderStatus {
    var title: String {
        switch self {
        case .active: "计费中"
        case .paused: "已暂停"
        case .pendingPayment: "待支付"
        case .completed: "已结账"
        case .cancelled: "已取消"
        }
    }
}

extension PaymentStatus {
    var title: String {
        switch self {
        case .pending: "待支付"
        case .paid: "已支付"
        case .refunded: "已退款"
        case .failed: "支付失败"
        }
    }
}
