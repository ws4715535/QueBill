import Foundation
import Observation

enum AppAccount: String, Hashable, Sendable {
    case admin
    case demo

    var displayName: String {
        switch self {
        case .admin: "管理员"
        case .demo: "测试账号"
        }
    }

    var dataLabel: String {
        switch self {
        case .admin: "独立业务数据"
        case .demo: "演示数据"
        }
    }
}

@MainActor
final class AccountDataStore {
    private var viewModels: [AppAccount: MachineDashboardViewModel] = [:]

    func viewModel(for account: AppAccount) -> MachineDashboardViewModel {
        if let existing = viewModels[account] { return existing }

        let viewModel: MachineDashboardViewModel
        do {
            let database = try AppDatabase.makeDefault(accountKey: account.rawValue)
            viewModel = MachineDashboardViewModel(
                repository: GRDBMachineRepository(database: database, seedDemoData: account == .demo),
                orderRepository: GRDBOrderRepository(database: database, seedDemoData: account == .demo),
                pricingRepository: GRDBPricingConfigurationRepository(database: database),
                paymentConfigurationRepository: GRDBPaymentCollectionConfigurationRepository(database: database)
            )
        } catch {
            viewModel = MachineDashboardViewModel(
                repository: InMemoryMachineRepository(machines: account == .demo ? Machine.demoMachines : []),
                orderRepository: InMemoryOrderRepository(),
                pricingRepository: InMemoryPricingConfigurationRepository(),
                paymentConfigurationRepository: InMemoryPaymentCollectionConfigurationRepository()
            )
        }

        viewModels[account] = viewModel
        return viewModel
    }
}

@MainActor
@Observable
final class AppSession {
    private static let persistedAccountKey = "authenticatedAccount"

    private(set) var account: AppAccount?
    private(set) var loginError: String?

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uiTestingDemo") {
            account = .demo
        } else if ProcessInfo.processInfo.arguments.contains("-uiTestingAdmin") {
            account = .admin
        } else if
            let rawValue = UserDefaults.standard.string(forKey: Self.persistedAccountKey),
            let persistedAccount = AppAccount(rawValue: rawValue)
        {
            account = persistedAccount
        }
    }

    var isAuthenticated: Bool { account != nil }

    @discardableResult
    func signIn(username: String, password: String) -> Bool {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchedAccount: AppAccount?

        switch (normalized, password) {
        case ("tiantian", "ounijiang"):
            matchedAccount = .admin
        case ("demo", "demo123"):
            matchedAccount = .demo
        default:
            matchedAccount = nil
        }

        guard let matchedAccount else {
            loginError = "账号或密码不正确"
            return false
        }

        account = matchedAccount
        UserDefaults.standard.set(matchedAccount.rawValue, forKey: Self.persistedAccountKey)
        loginError = nil
        return true
    }

    func signOut() {
        account = nil
        UserDefaults.standard.removeObject(forKey: Self.persistedAccountKey)
        loginError = nil
    }

    func clearError() {
        loginError = nil
    }
}
