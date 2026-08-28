import Foundation

/// Selects which bearer token to present to the platform (WebSocket auth) and KAS
/// (rewrap requests). The app will hold two credentials with different audiences:
/// a device CWT (Task 6, `aud: arkavo:devicecheck`) and a human CWT from WebAuthn
/// sign-in. This is the single accessor that decides between them so call sites
/// never need to know the rule.
public enum PlatformTokenProvider {
    /// Device CWT when present and its recorded expiry is in the future; else the human CWT.
    ///
    /// Boundary: an expiry exactly equal to `now` is treated as expired (the comparison
    /// requires `expiresAt` to be strictly after `now`), so a token is never presented
    /// during the instant it lapses.
    public static func bearerForPlatform(now: Date = .now,
                                          device: () -> (token: String, expiresAt: Date)? = KeychainManager.getDeviceAttestationToken,
                                          human: () -> String? = KeychainManager.getAuthenticationToken) -> String? {
        if let device = device(), device.expiresAt > now {
            return device.token
        }
        return human()
    }
}
