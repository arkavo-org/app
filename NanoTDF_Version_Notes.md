# NanoTDF Version Notes - OpenTDFKit Main Branch

## Summary

The ArkavoSocial package now uses OpenTDFKit from the `main` branch. The current public API only supports **NanoTDF v13 ("L1M")** format.

## NanoTDF Format Versions

### v12 (L1L) - Legacy Format
- **Magic bytes**: `L1L` (`0x4C 0x31 0x4C`)
- **Header structure**: KAS URL only (no public key in header)
- **HKDF salt**: `"L1L"` (for key derivation)
- **Use case**: Older deployments where KAS public key is obtained out-of-band

### v13 (L1M) - Current Format
- **Magic bytes**: `L1M` (`0x4C 0x31 0x4D`)
- **Header structure**: KAS URL + Curve + KAS Public Key (33-67 bytes depending on curve)
- **HKDF salt**: `"L1M"` (for key derivation)
- **Use case**: Modern deployments with KAS public key embedded in TDF

## OpenTDFKit Main Branch Status

### What Works ✅
- Creating NanoTDF v13 (L1M) via `createNanoTDF(kas:policy:plaintext:)`
- Decrypting both v12 and v13 NanoTDFs via `getPlaintext(using:)`
- Policy binding (GMAC and ECDSA)
- Signature support via `addSignatureToNanoTDF()`

### What's Limited ⚠️
- **v12 Creation**: The public API (`createNanoTDF`) requires `KasMetadata` which includes a public key, forcing v13 format
- **Internal structures**: `PolicyBindingConfig`, `SignatureAndPayloadConfig`, `PayloadKeyAccess` have `internal` initializers
- Manual NanoTDF construction is not possible from external packages

### Implementation Details

The version is automatically determined during serialization in `Header.toData()`:

```swift
// From OpenTDFKit/NanoTDF.swift lines 428-438
if payloadKeyAccess.kasPublicKey.isEmpty {
    // Serialize as v12 "L1L"
    data.append(Header.versionV12) // 0x4C
    data.append(payloadKeyAccess.kasLocator.toData())
} else {
    // Serialize as v13 "L1M"
    data.append(Header.version) // 0x4D
    data.append(payloadKeyAccess.toData())
}
```

## Current Implementation

### ArkavoClient.swift
Both encryption methods now create **v13 (L1M)** format:

1. `encryptRemotePolicy(payload:remotePolicyBody:)` - Remote policy NanoTDF
2. `encryptAndSendPayload(payload:policyData:kasMetadata:)` - Embedded policy NanoTDF

Example:
```swift
let kasMetadata = try KasMetadata(
    resourceLocator: ResourceLocator(...),
    publicKey: kasPublicKey as Any,  // Required - forces v13
    curve: .secp256r1
)

let nanoTDF = try await createNanoTDF(
    kas: kasMetadata,
    policy: &policy,
    plaintext: payload
)
```

## Backend Compatibility

### Recommendation
Ensure backend services (KAS, resource servers) support **both v12 and v13** formats for decryption:

- **Parser**: Check magic bytes (`L1L` vs `L1M`) to determine version
- **HKDF salt**: Use appropriate salt based on version detected
- **KAS public key**: For v12, obtain KAS public key from configuration; for v13, extract from header

### Migration Path
If v12 format is strictly required:

1. **Option A**: Request OpenTDFKit team to expose v12 creation API
   - Add public initializers for internal structs
   - OR add `createNanoTDFV12(kasResourceLocator:policy:plaintext:)` function

2. **Option B**: Fork OpenTDFKit and make necessary structs/initializers public
   - Not recommended due to maintenance burden

3. **Option C**: Backend supports both formats (RECOMMENDED)
   - Most flexible and future-proof
   - v13 provides better security by including KAS public key binding

## Files Modified

- `ArkavoSocial/Package.swift` - Updated to use `main` branch
- `ArkavoSocial/Sources/ArkavoSocial/ArkavoClient.swift` - Updated encryption methods
  - Line 943: Comment documenting v13 usage
  - Line 965: `createNanoTDF` call (v13 format)
  - Line 993: `createNanoTDF` call (v13 format)

## Testing

Build verification:
```bash
swift build --package-path ArkavoSocial
# Build complete! (2.15s) ✅
```

Integration points to test:
- [ ] KAS server can decrypt v13 NanoTDFs
- [ ] Policy enforcement works with v13 format
- [ ] Backward compatibility with existing v12 consumers (if any)

## Future Considerations

### NTDF Profile v1.2 (Issue #160)
The migration to NTDF authorization tokens will require:
- Chain of Trust support (Terminal → Intermediate → Origin links)
- Nested NanoTDF containers
- Attestation digest fields in Policy structure

This is NOT currently supported by OpenTDFKit and will require collaboration with the OpenTDF project.

## References

- OpenTDFKit Repository: https://github.com/arkavo-org/OpenTDFKit
- NanoTDF Spec: OpenTDF specification documents
- Related Issue: #160 (NTDF Authorization Tokens)
- Feature Request: `/Users/paul/Projects/arkavo/app/NTDF_OpenTDFKit_Feature_Request.md`

---

**Last Updated**: 2025-10-30
**Status**: Using OpenTDFKit main branch with v13 (L1M) format
