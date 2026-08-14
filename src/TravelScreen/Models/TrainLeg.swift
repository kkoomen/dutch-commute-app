import Foundation

/// Live status of a train, derived from NS API data.
enum TrainStatus: Equatable {
    case onTime
    case delayed(minutes: Int)
    case cancelled
    case unknown

    var label: String {
        switch self {
        case .onTime: "On time"
        case .delayed(let minutes): "+\(minutes) min"
        case .cancelled: "Cancelled"
        case .unknown: "Unknown"
        }
    }
}

/// A single train leg shown in the UI, with its live status.
struct TrainLeg: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let direction: String
    let plannedDeparture: Date
    let actualDeparture: Date?
    let status: TrainStatus

    /// The time shown to the user: actual when delayed, otherwise planned.
    var displayedDeparture: Date { actualDeparture ?? plannedDeparture }

    init?(dto: LegDTO) {
        guard let planned = dto.origin?.plannedDateTime.flatMap(NSDateParser.parse) else { return nil }
        let actual = dto.origin?.actualDateTime.flatMap(NSDateParser.parse)
        name = dto.name ?? Self.productName(dto.product) ?? "Train"
        direction = dto.direction ?? ""
        plannedDeparture = planned
        actualDeparture = actual
        status = TrainStatusMapping.status(
            cancelled: dto.cancelled,
            plannedDeparture: planned,
            actualDeparture: actual
        )
    }

    /// Fallback display name from the product payload, e.g. "IC 1234".
    private static func productName(_ product: ProductDTO?) -> String? {
        guard let number = product?.number, !number.isEmpty else { return nil }
        let category = product?.categoryCode ?? ""
        return category.isEmpty ? number : "\(category) \(number)"
    }
}
