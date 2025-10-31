# NTDF Profile v1.2 - Chain of Trust Implementation Notes

## Summary
This document describes how to implement NTDF Profile v1.2's Chain of Trust using OpenTDFKit's **existing flexible NanoTDF structure** by nesting NanoTDF containers in payloads.

## Background
The NTDF (NanoTDF) Profile v1.2 specification supports a "Chain of Trust" model. **No OpenTDFKit changes are required** because the NanoTDF spec already allows arbitrary data in payloads, including nested NanoTDFs.

Per the spec (Section 3.3.1.5): "This section contains a Policy object. The data contained in the Policy allows for flexible definitions of a policy including a policy by reference, or an embedded policy."

The payload can contain any binary data, including another serialized NanoTDF.

## Use Case
We're implementing a zero-trust authorization system for the Arkavo iOS/macOS application that requires:

1. **Terminal Link** (Outermost) - Issued by IdP/backend
   - Contains authorization grant (role_code, aud_code, exp)
   - Attests to the Intermediate Link via `attestation_digest`

2. **Intermediate Link** (NPE Attestation) - Issued by client app
   - Attests to device/application integrity
   - Claims: platform_code, platform_state, device_id, app_ver
   - Attests to the Origin Link via `attestation_digest`

3. **Origin Link** (PE Attestation) - Issued by client app
   - Attests to authenticated user
   - Claims: user_id, auth_level
   - No further attestation (end of chain)

## OpenTDFKit Capabilities

After reviewing the OpenTDFKit codebase (specifically `NanoTDF.swift`), the current implementation **already supports chaining**:

✅ **What Works:**
- NanoTDF v13 ("L1M") format
- `createNanoTDF()` function for creating any NanoTDF
- Policy binding (GMAC/ECDSA)
- Payload encryption/decryption with arbitrary binary data
- Signature support via `addSignatureToNanoTDF()`
- **Flexible payload** - can contain ANY data, including nested NanoTDFs

## Implementation Approach

### Chain Construction via Nesting

**Key Insight:** Simply put a serialized NanoTDF in the payload of another NanoTDF.

```swift
// Step 1: Create Origin Link (innermost - PE attestation)
var pePolicy = Policy(
    type: .embeddedPlaintext,
    body: EmbeddedPolicyBody(body: peClaims), // user_id, auth_level
    remote: nil,
    binding: nil
)
let originLink = try await createNanoTDF(
    kas: kasMetadata,
    policy: &pePolicy,
    plaintext: Data("PE".utf8) // Or actual user data
)

// Step 2: Create Intermediate Link (NPE attestation)
// The payload IS the Origin Link
var npePolicy = Policy(
    type: .embeddedPlaintext,
    body: EmbeddedPolicyBody(body: npeClaims), // device_id, platform_state
    remote: nil,
    binding: nil
)
let intermediateLink = try await createNanoTDF(
    kas: kasMetadata,
    policy: &npePolicy,
    plaintext: originLink.toData() // NESTED NANOTDF
)

// Step 3: Send Intermediate Link to IdP
// IdP creates Terminal Link with Intermediate in payload
```

### Policy Contains Claims, Payload Contains Next Link

- **Origin Link (PE):**
  - Policy: `{"user_id": "alice", "auth_level": "biometric"}`
  - Payload: Actual user data or marker

- **Intermediate Link (NPE):**
  - Policy: `{"platform": "iOS", "device_id": "...", "app_ver": "1.0"}`
  - Payload: **Serialized Origin Link NanoTDF**

- **Terminal Link (from IdP):**
  - Policy: `{"role": "user", "aud": "api.arkavo.com", "exp": 1234567890}`
  - Payload: **Serialized Intermediate Link NanoTDF**

### No Structural Changes Needed

The existing OpenTDFKit API is sufficient:
- ✅ `createNanoTDF(kas:policy:plaintext:)` - Works for any link
- ✅ `getPlaintext(using:)` - Decrypts to get inner link
- ✅ `addSignatureToNanoTDF()` - Sign each link
- ✅ `Policy.type = .embeddedPlaintext` - Store claims in policy

## Benefits
- ✅ **No OpenTDFKit changes required** - works with existing API
- ✅ Enables zero-trust authorization with device attestation
- ✅ Supports DPoP (Demonstration of Proof-of-Possession) patterns
- ✅ Maintains backward compatibility with single-link NanoTDFs
- ✅ Aligns with NTDF Profile v1.2 specification
- ✅ Leverages existing NanoTDF flexibility per spec

## Implementation Status

### Completed
- ✅ `NTDFChainBuilder.swift` - Chain construction implementation
- ✅ `PEClaims` struct - Person Entity attestation claims
- ✅ `NPEClaims` struct - Non-Person Entity attestation claims
- ✅ `createAuthorizationChain()` - Creates 3-link chain

### Remaining Work
1. **Device Attestation** - Integrate Apple DeviceCheck/App Attest for `device_id`
2. **DPoP Generator** - Create proof-of-possession headers for HTTP requests
3. **Network Integration** - Update ArkavoClient to use NTDF chains for auth
4. **Backend Endpoint** - IdP endpoint to receive PE+NPE links and return Terminal Link

## References
- NanoTDF Specification: https://github.com/opentdf/spec/tree/main/schema/nanotdf
- Section 3.3.1.5 (Policy flexibility)
- Section 3.3.2 (Payload structure)
- Issue #160 in arkavo-org/app repository

## Architecture Decision

**Decision:** Use native NanoTDF nesting instead of custom attestation_digest fields.

**Rationale:**
- Spec already supports arbitrary payload data
- No need to modify OpenTDFKit
- Cleaner separation: policy = claims, payload = next link
- Standard NanoTDF decryption workflow extracts inner links

---

Created by: Arkavo team
Related Issue: arkavo-org/app#160
Status: Implementation in progress using standard NanoTDF nesting
