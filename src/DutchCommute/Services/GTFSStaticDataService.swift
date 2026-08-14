import Foundation

// MARK: - Static GTFS models (internal to the services layer)

struct GTFSStop: Equatable {
    let id: String
    let name: String
    let latitude: Double?
    let longitude: Double?
}

struct GTFSRoute: Equatable {
    let id: String
    let shortName: String?
    let longName: String?
    /// GTFS route_type (0 tram, 1 metro, 2 rail, 3 bus, 4 ferry, ...).
    let routeType: Int32
}

struct GTFSTrip: Equatable {
    let id: String
    let routeID: String
    /// Destination/headsign when available.
    let headsign: String?
}

struct GTFSStopTime: Equatable {
    let tripID: String
    let stopID: String
    let stopSequence: Int32
    /// Departure as seconds since midnight on the service day (may be > 24h).
    let departureSeconds: Int?
}

// MARK: - Parsed dataset

/// Parsed static GTFS dataset. GTFS-Realtime entities are joined to these
/// by `trip_id` / `stop_id`.
struct GTFSStaticData: Equatable {
    let stops: [String: GTFSStop]
    let routes: [String: GTFSRoute]
    let trips: [String: GTFSTrip]
    let stopTimes: [GTFSStopTime]

    static let empty = GTFSStaticData(stops: [:], routes: [:], trips: [:], stopTimes: [])

    /// Stop times of a trip in stop-sequence order.
    func stopTimes(tripID: String) -> [GTFSStopTime] {
        stopTimes
            .filter { $0.tripID == tripID }
            .sorted { $0.stopSequence < $1.stopSequence }
    }

    /// The final stop of a trip (used as its destination).
    func destination(of trip: GTFSTrip) -> String {
        if let headsign = trip.headsign, !headsign.isEmpty { return headsign }
        if let last = stopTimes(tripID: trip.id).last, let stop = stops[last.stopID] {
            return stop.name
        }
        return trip.routeID
    }
}

// MARK: - Service

/// Loads and parses static GTFS CSV files (stops.txt, routes.txt,
/// trips.txt, stop_times.txt).
enum GTFSStaticDataService {
    /// Reads the four standard CSV files from `directory`.
    static func load(from directory: URL) throws -> GTFSStaticData {
        let read = { (name: String) throws -> String in
            try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        }
        return try load(
            stopsCSV: read("stops.txt"),
            routesCSV: read("routes.txt"),
            tripsCSV: read("trips.txt"),
            stopTimesCSV: read("stop_times.txt")
        )
    }

    /// Parses CSV text fixtures; testable without files.
    static func load(stopsCSV: String, routesCSV: String, tripsCSV: String, stopTimesCSV: String) throws -> GTFSStaticData {
        let stops = try parse(rows: stopsCSV) { fields in
            GTFSStop(
                id: fields["stop_id"] ?? "",
                name: fields["stop_name"] ?? "",
                latitude: fields["stop_lat"].flatMap(Double.init),
                longitude: fields["stop_lon"].flatMap(Double.init)
            )
        }
        let routes = try parse(rows: routesCSV) { fields in
            GTFSRoute(
                id: fields["route_id"] ?? "",
                shortName: fields["route_short_name"],
                longName: fields["route_long_name"],
                routeType: fields["route_type"].flatMap(Int32.init) ?? 3
            )
        }
        let trips = try parse(rows: tripsCSV) { fields in
            GTFSTrip(
                id: fields["trip_id"] ?? "",
                routeID: fields["route_id"] ?? "",
                headsign: fields["trip_headsign"]
            )
        }
        let stopTimes = try parse(rows: stopTimesCSV) { fields in
            GTFSStopTime(
                tripID: fields["trip_id"] ?? "",
                stopID: fields["stop_id"] ?? "",
                stopSequence: fields["stop_sequence"].flatMap(Int32.init) ?? 0,
                departureSeconds: fields["departure_time"].flatMap(Self.secondsOfDay)
            )
        }
        return GTFSStaticData(
            stops: Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) }),
            routes: Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0) }),
            trips: Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) }),
            stopTimes: stopTimes
        )
    }

    /// "HH:MM:SS" (may exceed 24:00) → seconds since midnight.
    static func secondsOfDay(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 3,
              let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    // MARK: CSV

    /// Parses CSV text with a header row into structs. Handles quoted
    /// fields (names may contain commas).
    private static func parse<T>(rows csv: String, map: ([String: String]) throws -> T) throws -> [T] {
        var lines = Self.csvRows(csv)
        guard let header = lines.first else { return [] }
        let columns = header.map { $0.trimmingCharacters(in: .whitespaces) }
        lines.removeFirst()
        return try lines.compactMap { row in
            guard row.count == columns.count, !row.allSatisfy({ $0.isEmpty }) else { return nil }
            var fields: [String: String] = [:]
            for (index, column) in columns.enumerated() {
                fields[column] = row[index]
            }
            return try map(fields)
        }
    }

    /// Splits CSV content into rows of unquoted fields.
    static func csvRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        for character in csv {
            switch character {
            case "\"":
                inQuotes.toggle()
            case ",":
                if inQuotes {
                    field.append(character)
                } else {
                    row.append(field)
                    field = ""
                }
            case "\n":
                if inQuotes {
                    field.append(character)
                } else {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                }
            case "\r":
                break
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

// MARK: - GTFS route_type → app mode

extension TransportMode {
    /// Maps a GTFS `route_type` to the app's mode; nil for types the app
    /// does not display (cable car, funicular, ...).
    init?(gtfsRouteType: Int32) {
        switch gtfsRouteType {
        case 0: self = .tram
        case 1: self = .metro
        case 2: self = .train
        case 3: self = .bus
        case 4: self = .ferry
        default: return nil
        }
    }
}
