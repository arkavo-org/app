import Foundation

/// Selects which bearer token to present to the platform (WebSocket auth) and KAS
/// (rewrap requests). The app will hold two credentials with different audiences:
/// a device CWT (`aud: arkavo:devicecheck`) and a human CWT from WebAuthn sign-in.
/// This is the single accessor that decides between them so call sites never need
/// to know the rule.
public enum PlatformTokenProvider {
    /// Human CWT when one exists; otherwise the device CWT, and only while its
    /// recorded expiry is still in the future.
    ///
    /// Human-first, not device-first, for two reasons. The binding spec gives a
    /// device CWT *presented as its own subject* nothing but a static
    /// class-ceiling entitlement set, while the human CWT carries the person's
    /// full entitlements -- so preferring the device token would silently reduce
    /// a signed-in user's access. And the device dimension is recorded as
    /// gateway-enforced rather than as the KAS subject: extending the device
    /// CWT's `aud` to the platform audience is still a pending server change, so
    /// a device CWT presented to platform/KAS today is simply rejected, with no
    /// fallback left to try.
    ///
    /// Revisit this order once the server extends the device CWT's audience to
    /// the platform audience *and* the platform's class-ceiling entitlement mode
    /// is deployed; until both land, the device token is a last resort for the
    /// signed-out case only.
    ///
    /// Boundary: an expiry exactly equal to `now` is treated as expired (the
    /// comparison requires `expiresAt` to be strictly after `now`), so a token is
    /// never presented during the instant it lapses.
    public static func bearerForPlatform(now: Date = .now,
                                          device: () -> (token: String, expiresAt: Date)? = KeychainManager.getDeviceAttestationToken,
                                          human: () -> String? = KeychainManager.getAuthenticationToken) -> String? {
        if let human = human() {
            return human
        }
        if let device = device(), device.expiresAt > now {
            return device.token
        }
        return nil
    }
}
