import Foundation

protocol MachineRepository: Sendable {
    func seedIfNeeded() async throws
    func fetchMachines() async throws -> [Machine]
    func save(_ machine: Machine) async throws
    func delete(machineID: UUID) async throws
}

protocol OrderRepository: Sendable {
    func seedIfNeeded(machines: [Machine]) async throws
    func fetchOrders() async throws -> [Order]
    func fetchPauses(orderID: UUID) async throws -> [OrderPause]
    func fetchEvents(orderID: UUID) async throws -> [OrderEvent]
    func fetchBill(orderID: UUID) async throws -> Bill?
    func fetchPayments(billID: UUID) async throws -> [Payment]
    func save(_ order: Order) async throws
    func save(_ pause: OrderPause) async throws
    func save(_ event: OrderEvent) async throws
    func save(_ bill: Bill) async throws
    func save(_ payment: Payment) async throws
    func delete(orderID: UUID) async throws
}

protocol PricingConfigurationRepository: Sendable {
    func fetch() async throws -> PricingConfiguration
    func save(_ configuration: PricingConfiguration) async throws
}

protocol PaymentCollectionConfigurationRepository: Sendable {
    func fetch() async throws -> PaymentCollectionConfiguration
    func save(_ configuration: PaymentCollectionConfiguration) async throws
}
