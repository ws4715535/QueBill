import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    let account: AppAccount
    let viewModel: MachineDashboardViewModel
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProductScreenHeader("我的", subtitle: "门店与系统设置")

            ScrollView {
                VStack(spacing: AppSpacing.medium) {
                    profile
                    NavigationLink { PriceRuleManagementView(viewModel: viewModel) } label: {
                        menuRow("计费规则", subtitle: "按机器类型设置单价与封顶", symbol: "creditcard")
                    }
                    NavigationLink { MachineManagementView(viewModel: viewModel) } label: {
                        menuRow(
                            "设备管理",
                            subtitle: "\(viewModel.machines.count) 台设备 · \(viewModel.activeCount) 台使用中",
                            symbol: "slider.horizontal.3"
                        )
                    }
                    NavigationLink { PaymentMethodManagementView(viewModel: viewModel) } label: {
                        menuRow(
                            "收款方式",
                            subtitle: "微信、支付宝收款码与线下收款",
                            symbol: "qrcode"
                        )
                    }
                    NavigationLink { HolidayManagementView() } label: {
                        menuRow("节假日设置", subtitle: "中国大陆 2026 年法定节假日", symbol: "calendar")
                    }
                    menuRow("账号与权限", subtitle: "3 个门店成员", symbol: "person.2")
                    menuRow("操作日志", subtitle: "最近 30 天记录", symbol: "clock.arrow.circlepath")
                    menuRow("系统设置", subtitle: "通知、数据与安全", symbol: "gearshape")

                    Button("退出登录", role: .destructive, action: onSignOut)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .padding(.top, AppSpacing.medium)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 760)
                .padding(AppSpacing.xLarge)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppColors.backgroundPrimary)
        .task { await viewModel.load() }
    }

    private var profile: some View {
        HStack(spacing: AppSpacing.medium) {
            Text("管")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(AppColors.accentStrong, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(account.displayName).font(.title3.bold())
                Text("天和雀庄").font(.subheadline).foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            StatusPill(title: account.rawValue, isActive: account == .demo)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 112)
        .productCard()
    }

    private func menuRow(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: symbol)
                .foregroundStyle(AppColors.accentStrong)
                .frame(width: 30, height: 30)
                .background(AppColors.accentSubtle, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).foregroundStyle(AppColors.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 64)
        .productCard()
    }
}

private struct PaymentMethodManagementView: View {
    let viewModel: MachineDashboardViewModel

    var body: some View {
        List {
            Section("扫码收款") {
                PaymentQRCodeEditor(
                    method: .weChat,
                    imageData: viewModel.paymentConfiguration.weChatQRCode,
                    viewModel: viewModel
                )
                PaymentQRCodeEditor(
                    method: .alipay,
                    imageData: viewModel.paymentConfiguration.alipayQRCode,
                    viewModel: viewModel
                )
            }

            Section("其他收款方式") {
                LabeledContent("现金", value: "已启用")
                LabeledContent("会员余额", value: "已启用")
            }

            Section {
                Text("收款码保存在当前账号的本地数据库中。结账选择微信或支付宝时，会显示对应收款码；更新后立即生效。")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .navigationTitle("收款方式")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PaymentQRCodeEditor: View {
    let method: PaymentMethod
    let imageData: Data?
    let viewModel: MachineDashboardViewModel

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Label(method.title, systemImage: method == .weChat ? "message.fill" : "a.circle.fill")
                    .font(.headline)
                Spacer()
                Text(imageData == nil ? "未配置" : "已配置")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(imageData == nil ? AppColors.textSecondary : AppColors.accentDefault)
            }

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.backgroundSubtle, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            }

            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(imageData == nil ? "上传收款码" : "更新收款码", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                if imageData != nil {
                    Button(role: .destructive) {
                        Task { await viewModel.savePaymentQRCode(nil, for: method) }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, AppSpacing.small)
        .task(id: selectedItem) {
            guard let selectedItem else { return }
            if let data = try? await selectedItem.loadTransferable(type: Data.self) {
                await viewModel.savePaymentQRCode(data, for: method)
            }
            self.selectedItem = nil
        }
    }
}

private struct MachineManagementView: View {
    let viewModel: MachineDashboardViewModel
    @State private var query = ""
    @State private var showsAddMachine = false
    @State private var machinePendingDelete: Machine?

    private var filteredMachines: [Machine] {
        guard !query.isEmpty else { return viewModel.machines }
        return viewModel.machines.filter {
            $0.number.localizedCaseInsensitiveContains(query)
                || $0.type.productTitle.localizedCaseInsensitiveContains(query)
                || ($0.note ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if filteredMachines.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "还没有设备" : "没有匹配的设备",
                    systemImage: query.isEmpty ? "square.stack.3d.up" : "magnifyingglass"
                )
            }
            ForEach(filteredMachines) { machine in
            NavigationLink {
                MachineEditorView(machine: machine, viewModel: viewModel)
            } label: {
                HStack(spacing: 14) {
                    Text(machine.number)
                        .font(.title3.bold())
                        .monospacedDigit()
                        .frame(width: 42, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(machine.type.productTitle).font(.subheadline.weight(.semibold))
                        Text(machine.note.flatMap { $0.isEmpty ? nil : $0 } ?? "无备注")
                            .font(.caption).foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    Label(machine.status.title, systemImage: machine.status.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(machine.status.tint)
                }
                .padding(.vertical, 6)
            }
            .disabled(machine.status == .inUse || machine.status == .paused)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    machinePendingDelete = machine
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(machine.status == .inUse || machine.status == .paused)
            }
            }
        }
        .searchable(text: $query, prompt: "搜索机器编号、类型或备注")
        .navigationTitle("机器管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsAddMachine = true
                } label: {
                    Label("新增机器", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showsAddMachine) {
            NavigationStack {
                MachineEditorView(machine: nil, viewModel: viewModel)
            }
        }
        .confirmationDialog(
            "删除这台机器？",
            isPresented: Binding(
                get: { machinePendingDelete != nil },
                set: { if !$0 { machinePendingDelete = nil } }
            ),
            presenting: machinePendingDelete
        ) { machine in
            Button("删除 \(machine.number)号机", role: .destructive) {
                Task { await viewModel.deleteMachine(machineID: machine.id) }
            }
            Button("取消", role: .cancel) {}
        } message: { machine in
            Text("删除后不会删除这台机器已有的历史订单，但设备档案将从当前账号移除。")
        }
    }
}

private struct MachineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let machine: Machine?
    let viewModel: MachineDashboardViewModel

    @State private var number: String
    @State private var type: MachineType
    @State private var status: MachineStatus
    @State private var note: String

    init(machine: Machine?, viewModel: MachineDashboardViewModel) {
        self.machine = machine
        self.viewModel = viewModel
        _number = State(initialValue: machine?.number ?? "")
        _type = State(initialValue: machine?.type ?? .fourSeat)
        _status = State(initialValue: machine?.status ?? .idle)
        _note = State(initialValue: machine?.note ?? "")
    }

    var body: some View {
        Form {
            Section("机器档案") {
                TextField("机器编号", text: $number)
                Picker("机器类型", selection: $type) {
                    ForEach(MachineType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("设备状态", selection: $status) {
                    Text("空闲").tag(MachineStatus.idle)
                    Text("维护中").tag(MachineStatus.maintenance)
                    Text("已停用").tag(MachineStatus.disabled)
                }
                TextField("备注", text: $note, axis: .vertical)
            }
            Section {
                Text("计费中的机器需先结账，才能修改机器档案。")
            }
        }
        .navigationTitle(machine == nil ? "新增机器" : "编辑 \(machine?.number ?? "")号机")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task {
                        if let machine {
                            await viewModel.saveMachine(
                                machineID: machine.id,
                                number: number,
                                type: type,
                                status: status,
                                note: note
                            )
                        } else {
                            await viewModel.createMachine(
                                number: number,
                                type: type,
                                status: status,
                                note: note
                            )
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PriceRuleManagementView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: MachineDashboardViewModel
    @State private var configuration: PricingConfiguration

    init(viewModel: MachineDashboardViewModel) {
        self.viewModel = viewModel
        _configuration = State(initialValue: viewModel.pricingConfiguration)
    }

    var body: some View {
        Form {
            Section("包时段") {
                Stepper(
                    "早场：\(configuration.earlyStartHour):00–\(configuration.earlyEndHour):00",
                    value: $configuration.earlyStartHour,
                    in: 0...23
                )
                Stepper("早场结束：\(configuration.earlyEndHour):00", value: $configuration.earlyEndHour, in: 1...23)
                currencyField("早场价格", value: $configuration.earlyPricePerPlayer, unit: "元 / 人")
                Stepper(
                    "夜场：\(configuration.nightStartHour):00–次日\(configuration.nightEndHour):00",
                    value: $configuration.nightStartHour,
                    in: 0...23
                )
                Stepper("夜场结束：次日\(configuration.nightEndHour):00", value: $configuration.nightEndHour, in: 0...23)
                currencyField("夜场价格", value: $configuration.nightPricePerPlayer, unit: "元 / 人")
            }

            Section("日间封顶") {
                currencyField("工作日", value: $configuration.weekdayDaytimeCapPerPlayer, unit: "元 / 人")
                currencyField("周末及节假日", value: $configuration.weekendHolidayDaytimeCapPerPlayer, unit: "元 / 人")
            }

            Section("四口机日间") {
                currencyField("工作日", value: $configuration.fourSeatWeekdayRatePerPlayer, unit: "元 / 人·小时")
                currencyField("周末及节假日", value: $configuration.fourSeatWeekendHolidayRatePerPlayer, unit: "元 / 人·小时")
            }

            Section("八口机日间") {
                currencyField("工作日", value: $configuration.eightSeatWeekdayRatePerPlayer, unit: "元 / 人·小时")
                currencyField("周末及节假日", value: $configuration.eightSeatWeekendHolidayRatePerPlayer, unit: "元 / 人·小时")
            }

            Section {
                Text("跨时段订单会分别计算早场、日间和夜场后叠加。修改仅影响新生成的账单，历史账单保留结账时的规则快照。")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .navigationTitle("计费规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task {
                        if await viewModel.savePricingConfiguration(configuration) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func currencyField(_ title: String, value: Binding<Decimal>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

private struct HolidayManagementView: View {
    private let holidays = [
        ("元旦", "1月1日 - 1月3日"),
        ("春节", "2月15日 - 2月23日"),
        ("清明节", "4月4日 - 4月6日"),
        ("劳动节", "5月1日 - 5月5日"),
        ("端午节", "6月19日 - 6月21日"),
        ("中秋节", "9月25日 - 9月27日"),
        ("国庆节", "10月1日 - 10月7日")
    ]

    var body: some View {
        List {
            Section("2026 年中国大陆法定节假日") {
                ForEach(holidays, id: \.0) { holiday in
                    HStack {
                        Text(holiday.0).fontWeight(.semibold)
                        Spacer()
                        Text(holiday.1).foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            Section("数据来源") {
                if let sourceURL = URL(string: "https://www.gov.cn/gongbao/2025/issue_12406/content_7048922.html") {
                    Link("国务院办公厅 2026 年节假日安排", destination: sourceURL)
                }
                Text("当前先使用官方年度配置。后续可增加远程同步，但本地会保留已发布配置，离线也能正确计费。")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .navigationTitle("节假日设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
