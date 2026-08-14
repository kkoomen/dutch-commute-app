import Foundation

enum GTFSRealtimeError: Error, LocalizedError {
    case malformedFeed
    case staleFeed
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .malformedFeed:
            return String(localized: "Couldn't parse the transit feed.")
        case .staleFeed:
            return String(localized: "The transit feed is stale.")
        case .network:
            return String(localized: "Network request failed.")
        }
    }
}

// MARK: - Decoded, protobuf-free feed data

/// Live update for one trip: delays / cancellations per stop.
struct GTFSRealtimeTripUpdate: Equatable {
    let tripID: String
    let routeID: String?
    /// True when the trip descriptor marks the whole trip cancelled.
    let tripCancelled: Bool
    let stopTimeUpdates: [GTFSRealtimeStopTimeUpdate]
    let timestamp: Date?
}

/// Live update for one stop of a trip.
struct GTFSRealtimeStopTimeUpdate: Equatable {
    let stopID: String?
    let stopSequence: Int32
    let arrivalDelay: Int32?
    let departureDelay: Int32?
    let arrivalTime: Date?
    let departureTime: Date?
    /// "SCHEDULED", "SKIPPED", "NO_DATA" or "UNSCHEDULED".
    let scheduleRelationship: String
}

/// A disruption (GTFS-Realtime Alert).
struct GTFSRealtimeAlert: Equatable {
    let id: String
    let header: String
    let summary: String
    let cause: String
    let effect: String
    let startDate: Date?
    let endDate: Date?
    let routeIDs: [String]
    let stopIDs: [String]
}

/// A live vehicle position.
struct GTFSRealtimeVehiclePosition: Equatable {
    let tripID: String?
    let routeID: String?
    let stopID: String?
    let latitude: Double?
    let longitude: Double?
    let bearing: Float?
    let timestamp: Date?
}

/// Everything decoded from one feed fetch.
struct GTFSRealtimeFeedData: Equatable {
    let feedTimestamp: Date?
    let tripUpdates: [GTFSRealtimeTripUpdate]
    let alerts: [GTFSRealtimeAlert]
    let vehiclePositions: [GTFSRealtimeVehiclePosition]
}

// MARK: - Client

/// Fetches and decodes GTFS-Realtime `.pb` feeds (SwiftProtobuf) and maps
/// them to plain structs. Handles network errors, malformed feeds and
/// stale feed headers; never exposes protobuf types.
struct GTFSRealtimeClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(_ feed: GTFSRealtimeFeed, now: Date = Date()) async throws -> GTFSRealtimeFeedData {
        let data: Data
        do {
            let (body, response) = try await session.data(from: feed.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw GTFSRealtimeError.network(URLError(.badServerResponse))
            }
            data = body
        } catch let error as GTFSRealtimeError {
            throw error
        } catch {
            throw GTFSRealtimeError.network(error)
        }
        return try Self.decode(data, feed: feed, now: now)
    }

    /// Decodes feed bytes; testable without network.
    static func decode(_ data: Data, feed: GTFSRealtimeFeed, now: Date = Date()) throws -> GTFSRealtimeFeedData {
        let message: TransitRealtime_FeedMessage
        do {
            message = try TransitRealtime_FeedMessage(serializedData: data)
        } catch {
            throw GTFSRealtimeError.malformedFeed
        }

        // Staleness: a feed with an old header timestamp is not trustworthy.
        if message.header.timestamp != 0 {
            let stamp = Date(timeIntervalSince1970: TimeInterval(message.header.timestamp))
            if now.timeIntervalSince(stamp) > feed.maxAge {
                throw GTFSRealtimeError.staleFeed
            }
        }

        return GTFSRealtimeFeedData(
            feedTimestamp: message.header.timestamp == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(message.header.timestamp)),
            tripUpdates: message.entity.compactMap(Self.mapTripUpdate),
            alerts: message.entity.compactMap(Self.mapAlert),
            vehiclePositions: message.entity.compactMap(Self.mapVehiclePosition)
        )
    }

    // MARK: Mapping (protobuf → plain structs)

    private static func mapTripUpdate(_ entity: TransitRealtime_FeedEntity) -> GTFSRealtimeTripUpdate? {
        guard entity.hasTripUpdate else { return nil }
        let update = entity.tripUpdate
        guard update.hasTrip, !update.trip.tripID.isEmpty else { return nil }
        return GTFSRealtimeTripUpdate(
            tripID: update.trip.tripID,
            routeID: update.trip.routeID.isEmpty ? nil : update.trip.routeID,
            tripCancelled: update.trip.scheduleRelationship == .canceled,
            stopTimeUpdates: update.stopTimeUpdate.map(mapStopTimeUpdate),
            timestamp: update.timestamp == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(update.timestamp))
        )
    }

    private static func mapStopTimeUpdate(_ update: TransitRealtime_TripUpdate.StopTimeUpdate) -> GTFSRealtimeStopTimeUpdate {
        let relationship = update.scheduleRelationship.rawValue
        return GTFSRealtimeStopTimeUpdate(
            stopID: update.stopID.isEmpty ? nil : update.stopID,
            stopSequence: Int32(update.stopSequence),
            arrivalDelay: update.hasArrival && update.arrival.hasDelay ? update.arrival.delay : nil,
            departureDelay: update.hasDeparture && update.departure.hasDelay ? update.departure.delay : nil,
            arrivalTime: update.hasArrival && update.arrival.time != 0
                ? Date(timeIntervalSince1970: TimeInterval(update.arrival.time)) : nil,
            departureTime: update.hasDeparture && update.departure.time != 0
                ? Date(timeIntervalSince1970: TimeInterval(update.departure.time)) : nil,
            scheduleRelationship: Self.stopTimeRelationshipNames[update.scheduleRelationship.rawValue] ?? "UNKNOWN"
        )
    }

    private static func mapAlert(_ entity: TransitRealtime_FeedEntity) -> GTFSRealtimeAlert? {
        guard entity.hasAlert else { return nil }
        let alert = entity.alert
        let entities = alert.informedEntity
        let firstPeriod = alert.activePeriod.first
        let startDate: Date?
        let endDate: Date?
        if let firstPeriod {
            startDate = firstPeriod.hasStart ? Date(timeIntervalSince1970: TimeInterval(firstPeriod.start)) : nil
            endDate = firstPeriod.hasEnd ? Date(timeIntervalSince1970: TimeInterval(firstPeriod.end)) : nil
        } else {
            startDate = nil
            endDate = nil
        }
        return GTFSRealtimeAlert(
            id: entity.id,
            header: alert.headerText.translation.first?.text ?? "",
            summary: alert.descriptionText.translation.first?.text ?? "",
            cause: Self.alertCauseNames[alert.cause.rawValue] ?? "UNKNOWN_CAUSE",
            effect: Self.alertEffectNames[alert.effect.rawValue] ?? "UNKNOWN_EFFECT",
            startDate: startDate,
            endDate: endDate,
            routeIDs: entities.compactMap { $0.routeID.isEmpty ? nil : $0.routeID },
            stopIDs: entities.compactMap { $0.stopID.isEmpty ? nil : $0.stopID }
        )
    }

    private static func mapVehiclePosition(_ entity: TransitRealtime_FeedEntity) -> GTFSRealtimeVehiclePosition? {
        guard entity.hasVehicle else { return nil }
        let vehicle = entity.vehicle
        return GTFSRealtimeVehiclePosition(
            tripID: vehicle.hasTrip && !vehicle.trip.tripID.isEmpty ? vehicle.trip.tripID : nil,
            routeID: vehicle.hasTrip && !vehicle.trip.routeID.isEmpty ? vehicle.trip.routeID : nil,
            stopID: vehicle.stopID.isEmpty ? nil : vehicle.stopID,
            latitude: vehicle.hasPosition ? Double(vehicle.position.latitude) : nil,
            longitude: vehicle.hasPosition ? Double(vehicle.position.longitude) : nil,
            bearing: vehicle.hasPosition && vehicle.position.hasBearing ? vehicle.position.bearing : nil,
            timestamp: vehicle.timestamp == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(vehicle.timestamp))
        )
    }

    // MARK: GTFS enum name tables (proto spellings, e.g. "NO_SERVICE")

    private static let stopTimeRelationshipNames: [Int: String] = [
        0: "SCHEDULED", 1: "SKIPPED", 2: "NO_DATA", 3: "UNSCHEDULED",
    ]

    private static let alertCauseNames: [Int: String] = [
        1: "UNKNOWN_CAUSE", 2: "OTHER_CAUSE", 3: "TECHNICAL_PROBLEM", 4: "STRIKE",
        5: "DEMONSTRATION", 6: "ACCIDENT", 7: "HOLIDAY", 8: "WEATHER", 9: "MAINTENANCE",
        10: "CONSTRUCTION", 11: "POLICE_ACTIVITY", 12: "MEDICAL_EMERGENCY",
    ]

    private static let alertEffectNames: [Int: String] = [
        1: "NO_SERVICE", 2: "REDUCED_SERVICE", 3: "SIGNIFICANT_DELAYS", 4: "DETOUR",
        5: "ADDITIONAL_SERVICE", 6: "MODIFIED_SERVICE", 7: "OTHER_EFFECT", 8: "UNKNOWN_EFFECT",
        9: "STOP_MOVED", 10: "NO_EFFECT", 11: "ACCESSIBILITY_ISSUE",
    ]
}
