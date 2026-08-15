import Foundation
import Security

/// Securely persists Live Activity push tokens in the Keychain.
/// Push tokens are per-activity, rotate over the activity's lifetime, and
/// are the only way a backend can push live updates to an activity.
enum LiveActivityPushTokenStore {
    private static let service = "com.dutchcommute.app.liveactivity"

    static func save(_ token: Data, for activityID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: activityID,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: token,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = token
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func token(for activityID: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: activityID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return data
    }

    static func delete(for activityID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: activityID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
