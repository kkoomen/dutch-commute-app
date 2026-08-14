import Foundation

// Minimal, tolerant DTOs for the NS Reisinformatie API v3.
// All fields are optional so a missing/renamed field never crashes decoding.
//
// IMPORTANT (verified against a live response, 2026-08-14):
// Times live on `origin` / `destination`, NOT on the leg itself:
//   leg.origin.plannedDateTime / leg.origin.actualDateTime
// See docs/api.md → "Response shape" for the full key reference.

struct TripsResponse: Decodable {
    let trips: [TripDTO]
}

struct TripDTO: Decodable {
    let status: String?       // "NORMAL" observed; informational
    let transfers: Int?
    let legs: [LegDTO]

    var firstLeg: LegDTO? { legs.first }
}

struct LegDTO: Decodable {
    let name: String?          // "IC 3008" (category + number)
    let direction: String?     // "Den Helder" (end destination of the train)
    let cancelled: Bool?       // full cancellation
    let partCancelled: Bool?   // partial cancellation (decoded, not yet shown)
    let origin: LegEndpointDTO?
    let destination: LegEndpointDTO?
    let product: ProductDTO?
}

struct LegEndpointDTO: Decodable {
    let name: String?          // "Zaandam"
    let stationCode: String?   // "ZD"
    let plannedDateTime: String?
    let actualDateTime: String?
}

struct ProductDTO: Decodable {
    let number: String?        // "3008"
    let categoryCode: String?  // "IC"
    let shortCategoryName: String?
    let longCategoryName: String?
}

struct StationDTO: Decodable {
    let code: String
    let namen: StationNamesDTO?
    let land: String?

    struct StationNamesDTO: Decodable {
        let nl: String?
        let en: String?
        let lang: String?
    }
}

/// v2 `/stations` wraps the station list in a `payload` object.
struct StationsResponse: Decodable {
    let payload: [StationDTO]
}
