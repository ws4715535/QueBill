import Foundation
import GRDB

actor GRDBPricingConfigurationRepository: PricingConfigurationRepository {
    private let database: AppDatabase
    private let key = "pricingConfiguration"

    init(database: AppDatabase) {
        self.database = database
    }

    func fetch() async throws -> PricingConfiguration {
        let record = try await database.queue.read { db in
            try AppSettingRecord.fetchOne(db, key: self.key)
        }
        guard let record else {
            let configuration = PricingConfiguration.standard
            try await save(configuration)
            return configuration
        }
        return try JSONDecoder().decode(PricingConfiguration.self, from: record.payload)
    }

    func save(_ configuration: PricingConfiguration) async throws {
        let record = AppSettingRecord(
            key: key,
            payload: try JSONEncoder().encode(configuration)
        )
        try await database.queue.write { db in
            try record.save(db)
        }
    }
}

private struct AppSettingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appSetting"
    let key: String
    let payload: Data
}

actor InMemoryPricingConfigurationRepository: PricingConfigurationRepository {
    private var configuration: PricingConfiguration

    init(configuration: PricingConfiguration = .standard) {
        self.configuration = configuration
    }

    func fetch() async throws -> PricingConfiguration { configuration }
    func save(_ configuration: PricingConfiguration) async throws {
        self.configuration = configuration
    }
}

actor GRDBPaymentCollectionConfigurationRepository: PaymentCollectionConfigurationRepository {
    private let database: AppDatabase
    private let key = "paymentCollectionConfiguration"

    init(database: AppDatabase) {
        self.database = database
    }

    func fetch() async throws -> PaymentCollectionConfiguration {
        let record = try await database.queue.read { db in
            try AppSettingRecord.fetchOne(db, key: self.key)
        }
        guard let record else { return .empty }
        return try JSONDecoder().decode(PaymentCollectionConfiguration.self, from: record.payload)
    }

    func save(_ configuration: PaymentCollectionConfiguration) async throws {
        let record = AppSettingRecord(
            key: key,
            payload: try JSONEncoder().encode(configuration)
        )
        try await database.queue.write { db in
            try record.save(db)
        }
    }
}

actor InMemoryPaymentCollectionConfigurationRepository: PaymentCollectionConfigurationRepository {
    private var configuration: PaymentCollectionConfiguration

    init(configuration: PaymentCollectionConfiguration = .empty) {
        self.configuration = configuration
    }

    func fetch() async throws -> PaymentCollectionConfiguration { configuration }
    func save(_ configuration: PaymentCollectionConfiguration) async throws {
        self.configuration = configuration
    }
}
