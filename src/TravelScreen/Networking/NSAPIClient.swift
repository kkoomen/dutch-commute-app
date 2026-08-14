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

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://gateway.apiportal.ns.nl/reisinformatie-api/api/v3")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
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

    /// The first trip departing at/after `date` on the given route.
    func fetchTrip(from: Station, to: Station, at date: Date) async throws -> TripDTO {
        var components = URLComponents(url: baseURL.appendingPathComponent("trips"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fromStation", value: from.code),
            URLQueryItem(name: "toStation", value: to.code),
            URLQueryItem(name: "dateTime", value: NSDateParser.queryString(date)),
            URLQueryItem(name: "searchForArrivalDeparture", value: "departure"),
            URLQueryItem(name: "lang", value: "en"),
        ]
        guard let url = components.url else { throw NSAPIError.invalidURL }
        let data = try await get(url: url)
        let response = try decode(TripsResponse.self, from: data)
        guard let trip = response.trips.first else { throw NSAPIError.noTrips }
        return trip
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
