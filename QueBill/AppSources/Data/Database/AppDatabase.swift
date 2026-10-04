import Foundation
import GRDB

final class AppDatabase: @unchecked Sendable {
    let queue: DatabaseQueue

    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try Self.makeMigrator().migrate(queue)
    }

    static func makeDefault(accountKey: String = "default") throws -> AppDatabase {
        guard let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AppDatabaseError.applicationSupportDirectoryUnavailable
        }

        let directory = baseURL.appendingPathComponent("QueBill", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let safeKey = accountKey.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return try AppDatabase(path: directory.appendingPathComponent("quebill-\(safeKey).sqlite").path)
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createMachine") { db in
            try db.create(table: "machine") { table in
                table.column("id", .text).primaryKey()
                table.column("number", .text).notNull().unique()
                table.column("type", .text).notNull()
                table.column("status", .text).notNull()
                table.column("note", .text)
                table.column("openedAt", .datetime)
                table.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("createOrderLedger") { db in
            try db.create(table: "orderLedger") { table in
                table.column("id", .text).primaryKey()
                table.column("machineID", .text).notNull()
                table.column("status", .text).notNull()
                table.column("startedAt", .datetime).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(index: "orderLedger_machineID", on: "orderLedger", columns: ["machineID"])
            try db.create(table: "orderPauseLedger") { table in
                table.column("id", .text).primaryKey()
                table.column("orderID", .text).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(table: "orderEventLedger") { table in
                table.column("id", .text).primaryKey()
                table.column("orderID", .text).notNull()
                table.column("occurredAt", .datetime).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(table: "billLedger") { table in
                table.column("id", .text).primaryKey()
                table.column("orderID", .text).notNull().unique()
                table.column("payload", .blob).notNull()
            }
            try db.create(table: "paymentLedger") { table in
                table.column("id", .text).primaryKey()
                table.column("billID", .text).notNull().unique()
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("createAppSetting") { db in
            try db.create(table: "appSetting") { table in
                table.column("key", .text).primaryKey()
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("supportSplitPayments") { db in
            try db.execute(sql: "ALTER TABLE paymentLedger RENAME TO paymentLedgerLegacy")
            try db.create(table: "paymentLedger") { table in
                table.column("id", .text).primaryKey()
                table.column("billID", .text).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.execute(sql: """
                INSERT INTO paymentLedger (id, billID, payload)
                SELECT id, billID, payload FROM paymentLedgerLegacy
                """)
            try db.drop(table: "paymentLedgerLegacy")
            try db.create(index: "paymentLedger_billID", on: "paymentLedger", columns: ["billID"])
        }
        return migrator
    }
}

enum AppDatabaseError: Error {
    case applicationSupportDirectoryUnavailable
}
