import Foundation

enum NSAPIError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpStatus(Int)
    case decoding
    case noTrips
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "NS_API_KEY is not configured. Add it to src/.env and rebuild."
        case .invalidURL:
            return "Invalid request URL."
        case .httpStatus(let code):
            return "NS API returned HTTP \(code)."
        case .decoding:
            return "Couldn't parse the NS API response."
        case .noTrips:
            return "No trains found for this journey."
        case .network:
            return "Network request failed."
        }
    }
}

/// Thin client for the NS Reisinformatie API v3.
struct NSAPIClient {
    let apiKey: String
    let baseURL: URL
    let session: URLSession

    /// Preferred-time trip searches are cached for 2 minutes per
    /// (from, to, preferred time) triple.
    let cache: TripsSearchCache

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://gateway.apiportal.ns.nl/reisinformatie-api/api/v3")!,
        session: URLSession = .shared,
        cache: TripsSearchCache = TripsSearchCache()
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.cache = cache
    }

    /// All Dutch train stations (for autocomplete).
    /// Stations come from the v2 endpoint — the only one that serves them on
    /// this subscription (all non-trips v3 routes return HTTP 404).
    /// Only the trips operation is documented in docs/api.md.
    func fetchStations() async throws -> [Station] {
        let url = URL(string: "https://gateway.apiportal.ns.nl/reisinformatie-api/api/v2/stations")!
        let data = try await get(url: url)
        let response = try decode(StationsResponse.self, from: data)
        return Self.nlStations(response.payload)
    }

    /// The first trip departing at/after `date` on the given route
    /// (optionally via an intermediate station, in the given modes).
    func fetchTrip(from: Station, to: Station, at date: Date, via: Station? = nil, transportModes: Set<TransportMode> = Set(TransportMode.allCases)) async throws -> TripDTO {
        guard let trip = try await fetchTrips(from: from, to: to, at: date, via: via, transportModes: transportModes).first else {
            throw NSAPIError.noTrips
        }
        return trip
    }

    /// Trips departing at/after `date` on the given route, earliest first.
    /// Mirrors the verified-working request shape (see docs/api.md):
    /// station *names* (not codes), `searchForArrival=false` for departure
    /// search, and a current/recent `dateTime` (old dates like 2000-01-01
    /// return HTTP 400). Optional `via` and `transportModes` are sent as
    /// `viaStation` and `disabledTransportModalities` (omitted when all
    /// modes are selected).
    func fetchTrips(from: Station, to: Station, at date: Date, via: Station? = nil, transportModes: Set<TransportMode> = Set(TransportMode.allCases)) async throws -> [TripDTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent("trips"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "fromStation", value: from.name),
            URLQueryItem(name: "toStation", value: to.name),
            URLQueryItem(name: "dateTime", value: NSDateParser.queryString(date)),
            URLQueryItem(name: "searchForArrival", value: "false"),
            URLQueryItem(name: "lang", value: "en"),
        ]
        if let via {
            items.append(URLQueryItem(name: "viaStation", value: via.name))
        }
        let disabled = TransportMode.disabledModalityCodes(keeping: transportModes)
        if !disabled.isEmpty {
            items.append(URLQueryItem(name: "disabledTransportModalities", value: disabled))
        }
        components.queryItems = items
        guard let url = components.url else { throw NSAPIError.invalidURL }
        let data = try await get(url: url)
        let response = try decode(TripsResponse.self, from: data)
        return response.trips
    }

    /// Distinct departure minutes-of-day (0..<1440, Amsterdam time) of the
    /// given trips, sorted ascending. Trips sharing the same departure minute
    /// count once; trips without a planned departure time are skipped.
    static func departureMinutes(of trips: [TripDTO], calendar: Calendar) -> [Int] {
        var seen = Set<Int>()
        var minutes: [Int] = []
        for trip in trips {
            guard let iso = trip.firstLeg?.origin?.plannedDateTime,
                  let date = NSDateParser.parse(iso)
            else { continue }
            let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            if seen.insert(minute).inserted {
                minutes.append(minute)
            }
        }
        return minutes.sorted()
    }

    /// Distinct departure minutes-of-day for a route at a preferred time,
    /// cached for 2 minutes per (from, to, via, modes, minute) tuple.
    func departureMinutes(from: Station, to: Station, via: Station? = nil, transportModes: Set<TransportMode> = Set(TransportMode.allCases), at preferred: Date) async throws -> [Int] {
        let calendar = JourneySchedule.calendar
        let minute = calendar.component(.hour, from: preferred) * 60 + calendar.component(.minute, from: preferred)
        let modesKey = transportModes.map(\.rawValue).sorted().joined(separator: "+")
        let key = "\(from.code)-\(to.code)-\(via?.code ?? "none")-\(modesKey)-\(minute)"
        if let cached = await cache.value(for: key) {
            return cached
        }
        let trips = try await fetchTrips(from: from, to: to, at: preferred, via: via, transportModes: transportModes)
        let minutes = Self.departureMinutes(of: trips, calendar: calendar)
        await cache.store(minutes, for: key)
        return minutes
    }

    /// Maps station DTOs to domain stations, keeping only Dutch stations.
    static func nlStations(_ dtos: [StationDTO]) -> [Station] {
        dtos.filter { $0.land == "NL" }.map { dto in
            Station(
                code: dto.code,
                name: dto.namen?.lang ?? dto.namen?.nl ?? dto.namen?.en ?? dto.code
            )
        }
    }

    // MARK: - Private

    private func get(path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw NSAPIError.invalidURL }
        return try await get(url: url)
    }

    private func get(url: URL) async throws -> Data {
        guard !apiKey.isEmpty else { throw NSAPIError.missingAPIKey }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSAPIError.httpStatus(http.statusCode)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw NSAPIError.decoding
        }
    }
}
