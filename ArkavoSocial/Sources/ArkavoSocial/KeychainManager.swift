import Foundation

// MARK: - Keychain Manager

public class KeychainManager {
    enum KeychainError: Error {
        case duplicateItem
        case unknown(OSStatus)
        case itemNotFound
    }

    static func save(value: String, service: String, account: String) {
        do {
            try save(value.data(using: .utf8)!, service: service, account: account)
        } catch {
            // ignore, use save(data...) throws
        }
    }

    static func save(_ data: Data, service: String, account: String) throws {
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecValueData as String: data as AnyObject,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let attributes: [String: AnyObject] = [
                kSecValueData as String: data as AnyObject,
            ]

            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.unknown(status)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    static func load(service: String, account: String) throws -> Data {
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecReturnData as String: kCFBooleanTrue,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.itemNotFound
        }

        return data
    }

    static func getValue(service: String, account: String) -> String? {
        do {
            let data = try load(service: service, account: account)
            return String(data: data, encoding: .utf8)!
        } catch {
            return nil
        }
    }

    static func delete(service: String, account: String) throws {
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - Token Management Convenience Methods

    static func getAccessToken() -> String? {
        do {
            let data = try load(service: "com.arkavo.patreon", account: "access_token")
            return String(data: data, encoding: .utf8)
        } catch {
//            print("Error retrieving access token:", error)
            return nil
        }
    }

    static func getRefreshToken() -> String? {
        do {
            let data = try load(service: "com.arkavo.patreon", account: "refresh_token")
            return String(data: data, encoding: .utf8)
        } catch {
//            print("Error retrieving refresh token:", error)
            return nil
        }
    }

    static func saveTokens(accessToken: String, refreshToken: String) throws {
        try save(accessToken.data(using: .utf8)!,
                 service: "com.arkavo.patreon",
                 account: "access_token")
        try save(refreshToken.data(using: .utf8)!,
                 service: "com.arkavo.patreon",
                 account: "refresh_token")
    }

    static func deleteTokens() {
        try? delete(service: "com.arkavo.patreon", account: "access_token")
        try? delete(service: "com.arkavo.patreon", account: "refresh_token")
        try? delete(service: "com.arkavo.patreon", account: "campaign_id")
    }

    public static func saveCampaignId(_ campaignId: String) throws {
        try save(campaignId.data(using: .utf8)!,
                 service: "com.arkavo.patreon",
                 account: "campaign_id")
    }

    public static func getCampaignId() -> String? {
        do {
            let data = try load(service: "com.arkavo.patreon", account: "campaign_id")
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error retrieving campaign ID:", error)
            return nil
        }
    }

    static func deleteTokensAndCampaignId() {
        try? delete(service: "com.arkavo.patreon", account: "access_token")
        try? delete(service: "com.arkavo.patreon", account: "refresh_token")
        try? delete(service: "com.arkavo.patreon", account: "campaign_id")
    }

    static func saveBlueskyTokens(accessToken: String, refreshToken: String) throws {
        try save(accessToken.data(using: .utf8)!,
                 service: "com.arkavo.bluesky",
                 account: "access_token")
        try save(refreshToken.data(using: .utf8)!,
                 service: "com.arkavo.bluesky",
                 account: "refresh_token")
    }

    static func getBlueskyAccessToken() -> String? {
        do {
            let data = try load(service: "com.arkavo.bluesky", account: "access_token")
            return String(data: data, encoding: .utf8)
        } catch {
//            print("Error retrieving access token:", error)
            return nil
        }
    }

    static func saveBlueskyHandle(_ handle: String) throws {
        try save(handle.data(using: .utf8)!,
                 service: "com.arkavo.bluesky",
                 account: "handle")
    }

    static func getBlueskyRefreshToken() -> String? {
        do {
            let data = try load(service: "com.arkavo.bluesky", account: "refresh_token")
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func getBlueskyHandle() -> String? {
        do {
            let data = try load(service: "com.arkavo.bluesky", account: "handle")
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func saveBlueskyDID(_ did: String) throws {
        try save(did.data(using: .utf8)!,
                 service: "com.arkavo.bluesky",
                 account: "did")
    }

    static func getBlueskyHDID() -> String? {
        do {
            let data = try load(service: "com.arkavo.bluesky", account: "did")
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func deleteBlueskyTokens() {
        try? delete(service: "com.arkavo.bluesky", account: "access_token")
        try? delete(service: "com.arkavo.bluesky", account: "refresh_token")
        try? delete(service: "com.arkavo.bluesky", account: "handle")
    }

    // Arkavo service
    public static func saveAuthenticationToken(_ token: String) throws {
        try save(token.data(using: .utf8)!,
                 service: "com.arkavo.webauthn",
                 account: "authentication_token")
    }

    public static func getAuthenticationToken() -> String? {
        do {
            let data = try load(service: "com.arkavo.webauthn", account: "authentication_token")
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    public static func deleteAuthenticationToken() {
        try? delete(service: "com.arkavo.webauthn", account: "authentication_token")
    }
}
