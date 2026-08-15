import Foundation

/// Abstraction over the push-update backend that keeps Live Activities
/// current via APNs. No backend is bundled with the app — implementing
/// this protocol requires a server that receives push tokens and sends
/// APNs pushes; see `docs/live-activities.md` for the contract
/// (endpoints and payloads).
protocol LiveActivityUpdateClient {
    /// Called whenever a (rotated) push token is observed for an activity.
    func register(pushToken: Data, for activityID: String, journeyID: UUID) async

    /// Called when an activity ends and its token should be removed.
    func unregister(activityID: String) async
}

/// The app ships without a backend; tokens are still collected and stored
/// so an implementation can be plugged in later.
struct NoopLiveActivityUpdateClient: LiveActivityUpdateClient {
    func register(pushToken: Data, for activityID: String, journeyID: UUID) async {}
    func unregister(activityID: String) async {}
}
