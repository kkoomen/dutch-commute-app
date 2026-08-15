import Foundation
import zlib

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
    /// Compact picker format: stop id → the GTFS route types serving it
    /// (derived from the full dataset; empty when only the full files are
    /// loaded — then choices are derived from stop times).
    let stopModes: [String: Set<Int32>]

    init(
        stops: [String: GTFSStop],
        routes: [String: GTFSRoute],
        trips: [String: GTFSTrip],
        stopTimes: [GTFSStopTime],
        stopModes: [String: Set<Int32>] = [:]
    ) {
        self.stops = stops
        self.routes = routes
        self.trips = trips
        self.stopTimes = stopTimes
        self.stopModes = stopModes
    }

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

/// Loads and parses static GTFS CSV files. Supports either the full
/// four-file format (stops/routes/trips/stop_times) or the compact picker
/// format (stops.txt + stop_modes.txt).
enum GTFSStaticDataService {
    /// Reads the dataset files from `directory` (missing files are skipped).
    static func load(from directory: URL) throws -> GTFSStaticData {
        let read = { (name: String) throws -> String in
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return "" }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return try load(
            stopsCSV: read("stops.txt"),
            routesCSV: read("routes.txt"),
            tripsCSV: read("trips.txt"),
            stopTimesCSV: read("stop_times.txt"),
            stopModesCSV: read("stop_modes.txt")
        )
    }

    /// Parses CSV text fixtures; testable without files.
    static func load(
        stopsCSV: String,
        routesCSV: String,
        tripsCSV: String,
        stopTimesCSV: String,
        stopModesCSV: String = ""
    ) throws -> GTFSStaticData {
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
        let stopModes = try parse(rows: stopModesCSV) { fields in
            let types = (fields["route_types"] ?? "")
                .split(separator: ",")
                .compactMap { Int32($0) }
            return (fields["stop_id"] ?? "", types)
        }
        return GTFSStaticData(
            stops: Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) }),
            routes: Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0) }),
            trips: Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) }),
            stopTimes: stopTimes,
            stopModes: Dictionary(uniqueKeysWithValues: stopModes.map { ($0.0, Set($0.1)) })
        )
    }

    /// "HH:MM:SS" (may exceed 24:00) → seconds since midnight.
    static func secondsOfDay(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 3,
              let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    // MARK: - Stop departures (bundled, compressed)

    /// Loads and decompresses the bundled stop-departures file
    /// (`departures.bin.gz`): per stop, the distinct departure minutes of
    /// day (0..<1440) across all service days, sorted. Format: repeated
    /// `stop_id int32`, `count uint16`, then `count × minute uint16`.
    static func loadDepartureMinutes(from url: URL) -> [String: [Int]] {
        guard let gz = try? Data(contentsOf: url),
              let data = gunzip(gz)
        else { return [:] }
        return parseDepartureMinutes(data)
    }

    /// Gzip decompression via zlib. The uncompressed size comes from the
    /// gzip trailer (ISIZE, last 4 bytes); windowBits 15+32 accepts gzip
    /// (and zlib) streams.
    static func gunzip(_ data: Data) -> Data? {
        guard data.count > 8 else { return nil }
        let size = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: data.count - 4, as: UInt32.self) })
        var output = Data(count: size)
        let status = output.withUnsafeMutableBytes { dst -> Int32 in
            data.withUnsafeBytes { src -> Int32 in
                var stream = z_stream()
                let initStatus = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                guard initStatus == Z_OK else { return initStatus }
                defer { inflateEnd(&stream) }
                stream.next_in = UnsafeMutablePointer(mutating: src.bindMemory(to: Bytef.self).baseAddress!)
                stream.avail_in = uInt(data.count)
                stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(size)
                return inflate(&stream, Z_FINISH)
            }
        }
        return status == Z_STREAM_END ? output : nil
    }

    /// Parses the binary stop-departures format (see loadDepartureMinutes).
    static func parseDepartureMinutes(_ data: Data) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        result.reserveCapacity(55_000)
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset + 6 <= raw.count {
                let stop = raw.loadUnaligned(fromByteOffset: offset, as: Int32.self)
                let count = Int(raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt16.self))
                offset += 6
                guard offset + count * 2 <= raw.count else { break }
                var minutes: [Int] = []
                minutes.reserveCapacity(count)
                for index in 0..<count {
                    minutes.append(Int(raw.loadUnaligned(fromByteOffset: offset + index * 2, as: UInt16.self)))
                }
                offset += count * 2
                result[String(stop)] = minutes
            }
        }
        return result
    }

    /// Departure minutes-of-day at a stop, from the preferred minute on,
    /// capped — used by the time picker for GTFS journeys.
    static func departureMinutes(
        from stopID: String,
        data: [String: [Int]],
        at preferred: Date,
        limit: Int = 8,
        calendar: Calendar = JourneySchedule.calendar
    ) -> [Int] {
        guard let minutes = data[stopID] else { return [] }
        let preferredMinute = calendar.component(.hour, from: preferred) * 60
            + calendar.component(.minute, from: preferred)
        return Array(minutes.filter { $0 >= preferredMinute }.prefix(limit))
    }

    /// Every stop served by a known route, one choice per (stop, mode)
    /// pair, sorted by name — used by the station picker. Prefers the
    /// compact stop_modes data; derives from stop times otherwise.
    static func stationChoices(from data: GTFSStaticData) -> [StationChoice] {
        var choices: [StationChoice] = []
        if !data.stopModes.isEmpty {
            for (stopID, types) in data.stopModes {
                guard let stop = data.stops[stopID] else { continue }
                for type in types {
                    guard let mode = TransportMode(gtfsRouteType: type) else { continue }
                    choices.append(StationChoice(id: stop.id, name: stop.name, mode: mode))
                }
            }
        } else {
            for stopTime in data.stopTimes {
                guard let trip = data.trips[stopTime.tripID],
                      let route = data.routes[trip.routeID],
                      let mode = TransportMode(gtfsRouteType: route.routeType),
                      let stop = data.stops[stopTime.stopID]
                else { continue }
                let choice = StationChoice(id: stop.id, name: stop.name, mode: mode)
                if !choices.contains(choice) {
                    choices.append(choice)
                }
            }
        }
        return choices.sorted { $0.name < $1.name }
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
        // Iterate scalars: CR and LF are separate scalars even in a \r\n
        // pair (String grapheme iteration would treat \r\n as one unit).
        for scalar in csv.unicodeScalars {
            switch Character(scalar) {
            case "\"":
                inQuotes.toggle()
            case ",":
                if inQuotes {
                    field.append(Character(scalar))
                } else {
                    row.append(field)
                    field = ""
                }
            case "\n":
                if inQuotes {
                    field.append(Character(scalar))
                } else {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                }
            case "\r":
                break
            default:
                field.append(Character(scalar))
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
