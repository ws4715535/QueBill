import Foundation

struct AppNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}
