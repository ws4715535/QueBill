import SwiftUI

struct MachineDashboardView: View {
    let viewModel: MachineDashboardViewModel

    @State private var showsMachineManagement = false
    @State private var machinePendingOpen: Machine?

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 340), spacing: AppSpacing.medium)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ProductScreenHeader("机器看板", subtitle: "实时营业状态，计时精确到秒") {
                Button {
                    showsMachineManagement = true
                } label: {
                    Label("管理机器", systemImage: "slider.horizontal.3")
                        .frame(minWidth: 128)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(AppColors.textPrimary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    statusHero
                    machineGrid
                }
                .padding(.horizontal, AppSpacing.xLarge)
                .padding(.vertical, 22)
            }
        }
        .background(AppColors.backgroundPrimary)
        .refreshable { await viewModel.reload() }
        .task { await viewModel.load() }
        .sheet(isPresented: $showsMachineManagement) {
            MachineManagementQuickView(viewModel: viewModel)
        }
        .alert(
            "确认开台",
            isPresented: Binding(
                get: { machinePendingOpen != nil },
                set: { if !$0 { machinePendingOpen = nil } }
            ),
            presenting: machinePendingOpen
        ) { machine in
            Button("取消", role: .cancel) {}
            Button("确认开台") {
                Task { await viewModel.open(machineID: machine.id) }
            }
        } message: { machine in
            Text("将为 \(machine.number) 号机创建新订单并立即开始计费。")
        }
    }

    private var statusHero: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("当前设备状态")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.accentSubtle)
                Text("\(viewModel.activeCount) 台使用中")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("\(viewModel.machines.count) 台设备，\(viewModel.availableCount) 台空闲，\(viewModel.attentionCount) 台不可用")
                    .font(.caption)
                    .foregroundStyle(AppColors.accentSubtle)
            }
            Spacer()
            Text("前台模式")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 18)
                .frame(height: 28)
                .background(AppColors.backgroundSubtle, in: Capsule())
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 116)
        .background(AppColors.accentStrong, in: RoundedRectangle(cornerRadius: AppRadius.hero))
    }

    @ViewBuilder
    private var machineGrid: some View {
        if viewModel.isLoading {
            MachineDashboardLoadingView(columns: columns)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("机器数据不可用", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重新加载") { Task { await viewModel.reload() } }
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            LazyVGrid(columns: columns, spacing: AppSpacing.medium) {
                ForEach(viewModel.machines) { machine in
                    if machine.status == .inUse || machine.status == .paused {
                        NavigationLink(value: AppRoute.machine(machine.id)) {
                            MachineDashboardCard(machine: machine, viewModel: viewModel) {}
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        MachineDashboardCard(machine: machine, viewModel: viewModel) {
                            machinePendingOpen = machine
                        }
                    }
                }
            }
        }
    }

}

private struct MachineDashboardCard: View {
    let machine: Machine
    let viewModel: MachineDashboardViewModel
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(machine.number)
                    .font(AppTypography.machineNumber)
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()
                Spacer()
                StatusPill(title: statusTitle, isActive: isActive)
            }

            Text(machine.type.productTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer(minLength: 0)

            if let openedAt = machine.openedAt, isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(durationText(from: openedAt, to: context.date))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                            .monospacedDigit()
                        HStack {
                            Text("\(viewModel.previewBill(machineID: machine.id, at: context.date)?.finalAmount.currencyText ?? "¥0.00") · 4人")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Label("查看详情", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(AppColors.accentDefault)
                    }
                }
            } else if machine.status == .idle {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("日间 \(idleDaytimeRate.currencyText) / 人·小时")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("封顶 \(idleDaytimeCap.currencyText) / 人 · 早场 \(viewModel.pricingConfiguration.earlyPricePerPlayer.currencyText) · 夜场 \(viewModel.pricingConfiguration.nightPricePerPlayer.currencyText)")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("开台", action: onOpen)
                        .buttonStyle(ProductPrimaryButtonStyle())
                        .frame(width: 106)
                }
            } else {
                Text(machine.note ?? "维护中，当前不可操作")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
        .productCard(
            borderColor: isActive ? AppColors.accentDefault : AppColors.border,
            background: isActive ? AppColors.accentSubtle : AppColors.surface
        )
        .accessibilityLabel(isActive ? "查看\(machine.number)号机详情" : "\(machine.number)号机")
    }

    private var isActive: Bool {
        machine.status == .inUse || machine.status == .paused
    }

    private var statusTitle: String {
        switch machine.status {
        case .idle: "空闲"
        case .inUse: "计费中"
        case .paused: "已暂停"
        case .maintenance, .disabled: "不可用"
        }
    }

    private var idleDaytimeRate: Decimal {
        let category = viewModel.pricingConfiguration.dayCategory(for: .now)
        return viewModel.pricingConfiguration.daytimeRate(machineType: machine.type, category: category)
    }

    private var idleDaytimeCap: Decimal {
        let category = viewModel.pricingConfiguration.dayCategory(for: .now)
        return viewModel.pricingConfiguration.daytimeCap(category: category)
    }

    private func durationText(from start: Date, to end: Date) -> String {
        let duration = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", duration / 3_600, (duration % 3_600) / 60, duration % 60)
    }
}

private struct MachineDashboardLoadingView: View {
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.medium) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppRadius.surface)
                    .fill(AppColors.backgroundSubtle)
                    .frame(height: 152)
                    .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel("正在载入机器")
    }
}

private struct MachineManagementQuickView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: MachineDashboardViewModel

    var body: some View {
        NavigationStack {
            List(viewModel.machines) { machine in
                HStack {
                    Text("\(machine.number)号机")
                        .font(.headline)
                    Text(machine.type.productTitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(machine.status.title)
                        .foregroundStyle(machine.status.tint)
                }
            }
            .navigationTitle("管理机器")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
