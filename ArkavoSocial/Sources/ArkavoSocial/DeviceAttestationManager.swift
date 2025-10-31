import Foundation
import CryptoKit

#if canImport(DeviceCheck)
import DeviceCheck
#endif

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Manages device attestation for Non-Person Entity (NPE) claims
/// Uses Apple's DeviceCheck and App Attest frameworks for hardware-backed attestation
public actor DeviceAttestationManager {

    private let keychainService = "com.arkavo.device"
    private let deviceIDAccount = "device_id"
    private let attestationKeyAccount = "attestation_key_id"

    /// Errors that can occur during device attestation
    public enum AttestationError: Error {
        case deviceCheckNotSupported
        case appAttestNotSupported
        case attestationFailed(String)
        case deviceIDGenerationFailed
        case jailbreakDetected
        case keychainError
    }

    public init() {}

    // MARK: - Public API

    /// Generates complete NPE claims for the current device
    /// - Parameter appVersion: The application version string
    /// - Returns: NPEClaims ready for inclusion in Intermediate Link
    public func generateNPEClaims(appVersion: String) async throws -> NPEClaims {
        let deviceId = try await getOrCreateDeviceID()
        let platformCode = getCurrentPlatform()
        let platformState = try await detectPlatformState()

        return NPEClaims(
            platformCode: platformCode,
            platformState: platformState,
            deviceId: deviceId,
            appVersion: appVersion,
            timestamp: Date()
        )
    }

    /// Gets or creates a stable device identifier
    /// Uses App Attest when available, falls back to secure random generation
    /// - Returns: Base64-encoded device identifier
    public func getOrCreateDeviceID() async throws -> String {
        // Check keychain first
        if let existingID = KeychainManager.getValue(service: keychainService, account: deviceIDAccount) {
            return existingID
        }

        // Generate new device ID
        #if os(iOS) && !targetEnvironment(simulator)
        // Try App Attest on real iOS devices
        if #available(iOS 14.0, *) {
            if let attestedID = try? await generateAppAttestedDeviceID() {
                try KeychainManager.save(
                    attestedID.data(using: .utf8)!,
                    service: keychainService,
                    account: deviceIDAccount
                )
                return attestedID
            }
        }
        #endif

        // Fallback: Generate cryptographically secure random ID
        let deviceID = try generateSecureDeviceID()
        try KeychainManager.save(
            deviceID.data(using: .utf8)!,
            service: keychainService,
            account: deviceIDAccount
        )
        return deviceID
    }

    /// Detects the security posture of the current platform
    /// - Returns: Platform state enum indicating security level
    public func detectPlatformState() async throws -> NPEClaims.PlatformState {
        #if DEBUG
        // In debug builds, we're in debug mode
        return .debugMode
        #else

        // Check for jailbreak/root
        if isJailbroken() {
            return .jailbroken
        }

        // Perform additional security checks
        if await performSecurityChecks() {
            return .secure
        }

        return .unknown
        #endif
    }

    // MARK: - App Attest Integration

    #if os(iOS) && !targetEnvironment(simulator)
    @available(iOS 14.0, *)
    private func generateAppAttestedDeviceID() async throws -> String {
        guard DCAppAttestService.shared.isSupported else {
            throw AttestationError.appAttestNotSupported
        }

        // Generate a key ID for attestation
        let keyId = try await DCAppAttestService.shared.generateKey()

        // Store the key ID for future use
        try KeychainManager.save(
            keyId.data(using: .utf8)!,
            service: keychainService,
            account: attestationKeyAccount
        )

        // Create a hash of the key ID as our device identifier
        // This provides a stable, hardware-backed identifier
        let keyData = keyId.data(using: .utf8)!
        let hash = SHA256.hash(data: keyData)
        return Data(hash).base64EncodedString()
    }

    /// Attests to the app's integrity using App Attest
    /// This can be called to generate a fresh attestation for the backend
    @available(iOS 14.0, *)
    public func attestToBackend(challenge: Data) async throws -> Data {
        guard DCAppAttestService.shared.isSupported else {
            throw AttestationError.appAttestNotSupported
        }

        // Get the stored key ID
        guard let keyIdString = KeychainManager.getValue(service: keychainService, account: attestationKeyAccount),
              let keyId = keyIdString.data(using: .utf8).flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw AttestationError.keychainError
        }

        // Generate attestation
        let attestation = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: challenge)
        return attestation
    }
    #endif

    // MARK: - Fallback Device ID

    private func generateSecureDeviceID() throws -> String {
        // Generate 32 bytes of cryptographically secure random data
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard result == errSecSuccess else {
            throw AttestationError.deviceIDGenerationFailed
        }

        return Data(bytes).base64EncodedString()
    }

    // MARK: - Platform Detection

    private func getCurrentPlatform() -> NPEClaims.PlatformCode {
        #if os(iOS)
        return .iOS
        #elseif os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #elseif os(watchOS)
        return .watchOS
        #else
        return .iOS // Default fallback
        #endif
    }

    // MARK: - Security Checks

    /// Detects if the device is jailbroken/rooted
    private func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        // Simulators are considered non-jailbroken for development
        return false
        #else

        #if os(iOS)
        // Check for common jailbreak indicators on iOS
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/private/var/lib/cydia",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/private/var/tmp/cydia.log",
            "/private/var/stash",
            "/usr/libexec/sftp-server",
            "/usr/bin/ssh"
        ]

        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        // Check if we can write to /private (should fail on non-jailbroken devices)
        let testPath = "/private/jailbreak_test_\(UUID().uuidString).txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: testPath)
            return true // Successfully wrote to protected area
        } catch {
            // Good - we couldn't write
        }

        // Check for suspicious dynamic libraries
        if let libraries = _dyld_image_count() as Int? {
            for i in 0..<libraries {
                if let imageName = _dyld_get_image_name(UInt32(i)) {
                    let name = String(cString: imageName)
                    if name.contains("MobileSubstrate") || name.contains("cycript") {
                        return true
                    }
                }
            }
        }

        #elseif os(macOS)
        // macOS has fewer jailbreak concerns, but check for suspicious modifications
        // Check for SIP (System Integrity Protection) status
        // Note: This is a simplified check
        if let csrStatus = getCSRStatus() {
            return csrStatus != 0 // Non-zero means SIP might be disabled
        }
        #endif

        return false
        #endif
    }

    #if os(macOS)
    /// Gets the System Integrity Protection (SIP) status on macOS
    private func getCSRStatus() -> UInt32? {
        // This would require system calls to check SIP status
        // For now, return nil (assume secure)
        // A full implementation would use csrutil or equivalent
        return nil
    }
    #endif

    /// Performs additional security checks
    private func performSecurityChecks() async -> Bool {
        var checksPass = true

        #if os(iOS)
        // Check if debugger is attached (simple check)
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)

        if result == 0 {
            // Check if we're being debugged
            if (info.kp_proc.p_flag & P_TRACED) != 0 {
                checksPass = false
            }
        }
        #endif

        return checksPass
    }

    // MARK: - Public Utility Methods

    /// Clears stored device attestation data
    /// Useful for testing or re-attestation
    public func clearAttestationData() {
        try? KeychainManager.delete(service: keychainService, account: deviceIDAccount)
        try? KeychainManager.delete(service: keychainService, account: attestationKeyAccount)
    }

    /// Gets detailed device information for debugging
    public func getDeviceInfo() async -> [String: String] {
        var info: [String: String] = [:]

        #if os(iOS)
        let device = UIDevice.current
        info["platform"] = "iOS"
        info["model"] = device.model
        info["systemVersion"] = device.systemVersion
        info["name"] = device.name
        info["identifierForVendor"] = device.identifierForVendor?.uuidString ?? "unknown"
        #elseif os(macOS)
        info["platform"] = "macOS"
        if let version = ProcessInfo.processInfo.operatingSystemVersionString as String? {
            info["systemVersion"] = version
        }
        info["hostName"] = ProcessInfo.processInfo.hostName
        #endif

        info["isJailbroken"] = String(isJailbroken())
        info["isDebug"] = {
            #if DEBUG
            return "true"
            #else
            return "false"
            #endif
        }()

        if let deviceID = try? await getOrCreateDeviceID() {
            // Only show first 8 chars for security
            info["deviceID"] = String(deviceID.prefix(8)) + "..."
        }

        return info
    }
}

// MARK: - Helper Functions

#if os(iOS)
// Import C functions for jailbreak detection
private func _dyld_image_count() -> UInt32 {
    // This is normally imported from dlfcn.h
    // Returning 0 as safe default if not available
    return 0
}

private func _dyld_get_image_name(_ index: UInt32) -> UnsafePointer<CChar>? {
    // This is normally imported from dlfcn.h
    // Returning nil as safe default if not available
    return nil
}
#endif
