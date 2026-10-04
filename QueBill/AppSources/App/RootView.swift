import PopupView
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case orders
    case operations
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: "首页"
        case .orders: "订单"
        case .operations: "报表"
        case .settings: "我的"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "house"
        case .orders: "list.bullet.rectangle"
        case .operations: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .dashboard: "house.fill"
        case .orders: "list.bullet.rectangle.fill"
        case .operations: "chart.xyaxis.line"
        case .settings: "gearshape.fill"
        }
    }
}

enum AppRoute: Hashable {
    case machine(UUID)
    case completedOrder(OrderSnapshot)
}

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var session = AppSession()
    @State private var selection: AppSection
    @State private var navigationPath = NavigationPath()
    let dataStore: AccountDataStore
    private var dashboardViewModel: MachineDashboardViewModel {
        dataStore.viewModel(for: session.account ?? .demo)
    }
    private let uiTestingMachineNumber: String?
    private let uiTestingCheckoutMachineNumber: String?

    init(dataStore: AccountDataStore) {
        self.dataStore = dataStore
        let arguments = ProcessInfo.processInfo.arguments
        let section: AppSection
        if let index = arguments.firstIndex(of: "-uiTestingSection"), arguments.indices.contains(index + 1) {
            section = AppSection(rawValue: arguments[index + 1]) ?? .dashboard
        } else {
            section = .dashboard
        }
        if let index = arguments.firstIndex(of: "-uiTestingMachine"), arguments.indices.contains(index + 1) {
            uiTestingMachineNumber = arguments[index + 1]
        } else {
            uiTestingMachineNumber = nil
        }
        if let index = arguments.firstIndex(of: "-uiTestingCheckout"), arguments.indices.contains(index + 1) {
            uiTestingCheckoutMachineNumber = arguments[index + 1]
        } else {
            uiTestingCheckoutMachineNumber = nil
        }
        _selection = State(initialValue: section)
    }

    var body: some View {
        Group {
            if let account = session.account {
                appShell(account: account)
            } else {
                LoginView(session: session)
            }
        }
        .tint(AppColors.accentStrong)
        .popup(isPresented: noticeBinding) {
            if let notice = dashboardViewModel.notice {
                AppToastView(notice: notice)
            }
        } customize: {
            $0
                .type(.toast)
                .position(.top)
                .autohideIn(2.0)
                .closeOnTap(true)
        }
    }

    private func appShell(account: AppAccount) -> some View {
        if let uiTestingCheckoutMachineNumber {
            return AnyView(TestingCheckoutHost(
                machineNumber: uiTestingCheckoutMachineNumber,
                viewModel: dashboardViewModel
            ))
        }
        if let uiTestingMachineNumber {
            return AnyView(TestingMachineDetailHost(
                machineNumber: uiTestingMachineNumber,
                viewModel: dashboardViewModel
            ))
        }
        if horizontalSizeClass == .regular {
            return AnyView(
                NavigationSplitView {
                    List(AppSection.allCases) { section in
                        Button {
                            selection = section
                        } label: {
                            Label(
                                section.title,
                                systemImage: selection == section ? section.selectedSymbol : section.symbol
                            )
                            .foregroundStyle(selection == section ? AppColors.accentStrong : AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selection == section ? AppColors.accentSubtle : Color.clear)
                    }
                    .safeAreaInset(edge: .top) {
                        HStack(spacing: 10) {
                            Image("TihoLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("天和雀庄")
                                    .font(.headline.weight(.bold))
                                Text("门店运营管理系统")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppColors.surface)
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.displayName).font(.subheadline.bold())
                            Text(account.dataLabel).font(.caption).foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                } detail: {
                    sectionNavigation(account: account)
                }
                .navigationSplitViewStyle(.balanced)
                .onChange(of: selection) { _, _ in navigationPath = NavigationPath() }
            )
        }
        return AnyView(
            VStack(spacing: 0) {
                sectionNavigation(account: account)
                ProductTabBar(selection: $selection)
            }
            .background(AppColors.backgroundPrimary)
            .onChange(of: selection) { _, _ in navigationPath = NavigationPath() }
        )
    }

    private func sectionNavigation(account: AppAccount) -> some View {
        VStack(spacing: 0) {
            AccountContextStrip(account: account)
            NavigationStack(path: $navigationPath) {
                sectionView(selection, account: account)
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .machine(let machineID):
                            MachineDetailView(
                                machineID: machineID,
                                viewModel: dashboardViewModel,
                                onCompletedOrder: replaceWithCompletedOrder
                            )
                        case .completedOrder(let snapshot):
                            OrderDetailView(snapshot: snapshot)
                        }
                    }
            }
        }
    }

    @MainActor
    private func replaceWithCompletedOrder(_ snapshot: OrderSnapshot) {
        navigationPath = NavigationPath()
        navigationPath.append(AppRoute.completedOrder(snapshot))
    }

    private struct ProductTabBar: View {
        @Binding var selection: AppSection

        var body: some View {
            HStack(spacing: 0) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: selection == section ? section.selectedSymbol : section.symbol)
                                .font(.system(size: 20, weight: .semibold))
                            Text(section.title)
                                .font(.caption2.weight(selection == section ? .semibold : .regular))
                        }
                        .foregroundStyle(selection == section ? AppColors.accentStrong : AppColors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .background(AppColors.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(AppColors.border).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection, account: AppAccount) -> some View {
        switch section {
        case .dashboard:
            MachineDashboardView(viewModel: dashboardViewModel)
        case .orders:
            OrdersView(viewModel: dashboardViewModel)
        case .operations:
            OperationsView(viewModel: dashboardViewModel)
        case .settings:
            SettingsView(
                account: account,
                viewModel: dashboardViewModel,
                onSignOut: session.signOut
            )
        }
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { dashboardViewModel.notice != nil },
            set: { isPresented in
                if !isPresented { dashboardViewModel.clearNotice() }
            }
        )
    }
}

private struct TestingCheckoutHost: View {
    let machineNumber: String
    let viewModel: MachineDashboardViewModel

    var body: some View {
        Group {
            if
                let machine = viewModel.machines.first(where: { $0.number == machineNumber }),
                let bill = viewModel.previewBill(machineID: machine.id)
            {
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
                    onCompleted: { _ in }
                )
            } else {
                ProgressView("正在生成账单")
            }
        }
        .task { await viewModel.load() }
    }
}

private struct TestingMachineDetailHost: View {
    let machineNumber: String
    let viewModel: MachineDashboardViewModel

    var body: some View {
        NavigationStack {
            if let machine = viewModel.machines.first(where: { $0.number == machineNumber }) {
                MachineDetailView(machineID: machine.id, viewModel: viewModel, onCompletedOrder: { _ in })
            } else {
                ProgressView("正在读取机器")
            }
        }
        .task { await viewModel.load() }
    }
}

private struct AppToastView: View {
    let notice: AppNotice

    var body: some View {
        Label(
            notice.message,
            systemImage: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, 12)
        .background(notice.isError ? AppColors.danger : AppColors.accentStrong)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 5)
        .padding(.top, AppSpacing.small)
    }
}
