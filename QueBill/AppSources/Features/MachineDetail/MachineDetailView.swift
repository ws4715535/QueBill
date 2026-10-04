import SwiftUI

struct MachineDetailView: View {
    let machineID: UUID
    let viewModel: MachineDashboardViewModel
    let onCompletedOrder: @MainActor (OrderSnapshot) -> Void

    @State private var showsPauseConfirmation = false
    @State private var showsStartTimeEditor = false
    @State private var showsNoteEditor = false
    @State private var showsCheckout = false

    var body: some View {
        Group {
            if let machine = viewModel.machine(id: machineID) {
                detail(machine)
            } else {
                ContentUnavailableView(
                    "找不到机器",
                    systemImage: "questionmark.square.dashed",
                    description: Text("机器档案可能已被修改。")
                )
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("机器详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ machine: Machine) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                machineHeading(machine)

                if machine.status == .idle {
                    idleContent(machine)
                } else if machine.status == .inUse || machine.status == .paused {
                    activeContent(machine)
                } else {
                    unavailableContent(machine)
                }
            }
            .padding(AppSpacing.xLarge)
            .padding(.bottom, 88)
        }
        .safeAreaInset(edge: .bottom) {
            if machine.status == .inUse || machine.status == .paused {
                actionBar(machine)
            }
        }
        .alert(
            machine.status == .paused ? "恢复这桌的计费？" : "暂停这桌的计费？",
            isPresented: $showsPauseConfirmation,
            presenting: machine
        ) { currentMachine in
            Button(currentMachine.status == .paused ? "恢复计费" : "确认暂停") {
                Task {
                    if currentMachine.status == .paused {
                        await viewModel.resume(machineID: currentMachine.id)
                    } else {
                        await viewModel.pause(machineID: currentMachine.id)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: { currentMachine in
            Text(currentMachine.status == .paused ? "恢复后将从当前时间继续计费。" : "暂停期间不会计入有效时长和账单金额。")
        }
        .sheet(isPresented: $showsStartTimeEditor) {
            StartTimeEditor(machine: machine) { date in
                Task { await viewModel.adjustOpenedAt(machineID: machine.id, to: date) }
            }
        }
        .sheet(isPresented: $showsNoteEditor) {
            MachineNoteEditor(machine: machine) { note in
                Task { await viewModel.updateNote(machineID: machine.id, note: note) }
            }
        }
        .fullScreenCover(isPresented: $showsCheckout) {
            if let bill = viewModel.previewBill(machineID: machine.id) {
                CheckoutSummarySheet(
                    machine: machine,
                    bill: bill,
                    paymentConfiguration: viewModel.paymentConfiguration,
                    onConfirm: { methods, adjustment in
                        await viewModel.checkout(
                            machineID: machine.id,
                            paymentMethods: methods,
                            adjustment: adjustment
                        )
                    },
                    onCompleted: { snapshot in
                        onCompletedOrder(snapshot)
                    }
                )
            }
        }
    }

    private func machineHeading(_ machine: Machine) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("机器 \(machine.number)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
                Text(machine.type.productTitle)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            Spacer()
            StatusPill(
                title: machine.status == .inUse ? "计费中" : machine.status.title,
                isActive: machine.status == .inUse || machine.status == .paused
            )
        }
    }

    private func activeContent(_ machine: Machine) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本桌当前应收")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.accentSubtle)
                    if let openedAt = machine.openedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(viewModel.previewBill(machineID: machine.id, at: context.date)?.finalAmount.currencyText ?? "¥0.00")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                Text("有效时长 \(durationText(from: openedAt, to: context.date))")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.accentSubtle)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Spacer()
                Text(machine.status == .paused ? "计费已暂停" : "实时计算")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.45))
                    .padding(.horizontal, 18)
                    .frame(height: 32)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(AppSpacing.large)
            .frame(maxWidth: .infinity, minHeight: 116)
            .background(Color(red: 0.07, green: 0.07, blue: 0.065), in: RoundedRectangle(cornerRadius: AppRadius.hero))

            VStack(spacing: 0) {
                KeyValueRow(title: "订单号", value: orderCode(for: machine))
                Divider()
                KeyValueRow(title: "开台时间", value: machine.openedAt?.formatted(date: .omitted, time: .shortened) ?? "待确认")
                Divider()
                KeyValueRow(title: "日间单价", value: daytimeRateText(for: machine))
                Divider()
                KeyValueRow(title: "日间封顶", value: daytimeCapText(for: machine))
                Divider()
                KeyValueRow(
                    title: "包时段",
                    value: "早场 \(viewModel.pricingConfiguration.earlyPricePerPlayer.currencyText) · 夜场 \(viewModel.pricingConfiguration.nightPricePerPlayer.currencyText) / 人"
                )
                Divider()
                KeyValueRow(title: "备注", value: machine.effectiveNote)
            }
            .padding(.horizontal, AppSpacing.medium)
            .productCard()

            HStack(spacing: AppSpacing.medium) {
                Button("调整开台时间") { showsStartTimeEditor = true }
                    .buttonStyle(ProductSecondaryButtonStyle())
                Button("编辑备注") { showsNoteEditor = true }
                    .buttonStyle(ProductSecondaryButtonStyle())
            }

            let events = activeEvents(for: machine)
            HStack {
                Text("操作记录")
                    .font(AppTypography.sectionTitle)
                Spacer()
                Text("\(events.count) 条")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if events.isEmpty {
                Text("暂无操作记录")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(AppSpacing.medium)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                    .background(AppColors.backgroundSubtle, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: event.kind.symbol)
                                .foregroundStyle(AppColors.accentDefault)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.kind.title).font(.subheadline.weight(.semibold))
                                Text(event.detail ?? event.occurredAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                            Text(event.occurredAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2).foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.vertical, 12)
                        if event.id != events.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, AppSpacing.medium)
                .productCard()
            }
        }
    }

    private func idleContent(_ machine: Machine) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            Text("这台机器当前空闲，可以立即开台。")
                .font(.title3)
                .foregroundStyle(AppColors.textSecondary)
            Button("开台") {
                Task { await viewModel.open(machineID: machine.id) }
            }
            .buttonStyle(ProductPrimaryButtonStyle())
            .frame(maxWidth: 360)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .productCard()
    }

    private func unavailableContent(_ machine: Machine) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            Label(machine.note ?? "机器当前不可使用", systemImage: "wrench.and.screwdriver")
                .font(.title3)
                .foregroundStyle(AppColors.textSecondary)
            if machine.status == .maintenance {
                Button("恢复为空闲") {
                    Task { await viewModel.restore(machineID: machine.id) }
                }
                .buttonStyle(ProductPrimaryButtonStyle())
                .frame(maxWidth: 360)
            }
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .productCard()
    }

    private func actionBar(_ machine: Machine) -> some View {
        HStack(spacing: AppSpacing.medium) {
            Button(machine.status == .paused ? "恢复" : "暂停") {
                showsPauseConfirmation = true
            }
            .buttonStyle(ProductSecondaryButtonStyle())

            Button("结账") { showsCheckout = true }
                .buttonStyle(ProductPrimaryButtonStyle())
        }
        .padding(.horizontal, AppSpacing.xLarge)
        .padding(.vertical, AppSpacing.medium)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColors.border).frame(height: 1)
        }
    }

    private func durationText(from start: Date, to end: Date) -> String {
        let duration = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", duration / 3_600, (duration % 3_600) / 60, duration % 60)
    }

    private func orderCode(for machine: Machine) -> String {
        guard let order = viewModel.activeOrder(machineID: machine.id) else { return machine.orderCode }
        return order.displayCode
    }

    private func activeEvents(for machine: Machine) -> [OrderEvent] {
        guard let order = viewModel.activeOrder(machineID: machine.id) else { return [] }
        return viewModel.eventsByOrderID[order.id] ?? []
    }

    private func daytimeRateText(for machine: Machine) -> String {
        guard let order = viewModel.activeOrder(machineID: machine.id) else { return machine.type.weekdayRateText }
        let category = viewModel.pricingConfiguration.dayCategory(for: order.businessDay.date)
        let rate = viewModel.pricingConfiguration.daytimeRate(machineType: machine.type, category: category)
        return "\(rate.currencyText) / 人·小时"
    }

    private func daytimeCapText(for machine: Machine) -> String {
        guard let order = viewModel.activeOrder(machineID: machine.id) else { return machine.type.daytimeCapText }
        let category = viewModel.pricingConfiguration.dayCategory(for: order.businessDay.date)
        return "\(viewModel.pricingConfiguration.daytimeCap(category: category).currencyText) / 人"
    }
}

private struct StartTimeEditor: View {
    @Environment(\.dismiss) private var dismiss
    let machine: Machine
    let onSave: (Date) -> Void
    @State private var date: Date

    init(machine: Machine, onSave: @escaping (Date) -> Void) {
        self.machine = machine
        self.onSave = onSave
        _date = State(initialValue: machine.openedAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "新开台时间",
                    selection: $date,
                    in: ...Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Section {
                    Text("修改后将自动更新当前计时，并在订单事件中保留调整记录。")
                }
            }
            .navigationTitle("调整开台时间")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct MachineNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let machine: Machine
    let onSave: (String) -> Void
    @State private var note: String

    init(machine: Machine, onSave: @escaping (String) -> Void) {
        self.machine = machine
        self.onSave = onSave
        _note = State(initialValue: machine.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("备注", text: $note, axis: .vertical)
            }
            .navigationTitle("编辑备注")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(note)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
