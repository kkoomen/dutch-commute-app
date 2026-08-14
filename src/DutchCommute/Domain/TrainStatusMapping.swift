import Foundation

/// Turns NS API trip data into a `TrainStatus`.
/// Rule order matters: cancellation wins over delays.
enum TrainStatusMapping {
    static func status(
        cancelled: Bool?,
        plannedDeparture: Date?,
        actualDeparture: Date?
    ) -> TrainStatus {
        if cancelled == true { return .cancelled }
        guard let planned = plannedDeparture else { return .unknown }
        guard let actual = actualDeparture else { return .onTime }
        let minutes = Int(actual.timeIntervalSince(planned) / 60.0)
        if minutes <= 0 { return .onTime }
        return .delayed(minutes: minutes)
    }
}
