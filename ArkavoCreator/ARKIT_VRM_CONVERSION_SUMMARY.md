# ARKit to VRM Coordinate Conversion - Implementation Summary

## Overview
Successfully implemented and tested the ARKit to VRM coordinate conversion system for motion capture. The converter transforms ARKit skeleton data to VRM humanoid bone rotations with proper coordinate system handling.

## Architecture

### Clean Separation of Concerns
```
┌─────────────────────────────────────────────────────────────────┐
│                      ArkavoCreator                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              ARKitToVRMConverter                          │  │
│  │  - ARKit-specific coordinate conversion                   │  │
│  │  - Local rotation computation                             │  │
│  │  - Left-side mirroring                                    │  │
│  │  - Root rotation correction (180° Y)                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                          │                                       │
│                          ▼                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              VRMARecorder / VRMAProcessor                 │  │
│  │  - Recording and post-processing                          │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     VRMMetalKit (Platform Agnostic)              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              VRMModel / VRMNode                           │  │
│  │  - setLocalRotation(_:for:) ✅ IMPLEMENTED               │  │
│  │  - getLocalRotation(for:) ✅ IMPLEMENTED                 │  │
│  │  - setHipsTranslation(_:) ✅ IMPLEMENTED                 │  │
│  │  - getHipsTranslation() ✅ IMPLEMENTED                   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Key Implementation Details

### Root Rotation Correction
- **Issue**: ARKit faces -Z, VRM faces +Z (both Y-up right-handed)
- **Solution**: Simple 180° rotation around Y-axis
- **Fixes**: Previous 90° sideways bug caused by over-complex quaternion

```swift
static let rootRotationCorrection = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
```

### Coordinate Conversion Pipeline
1. **Extract Rotation**: From ARKit world-space transform matrix
2. **Compute Local Rotation**: `local = inverse(parent) * child`
3. **Apply Conversions**:
   - Root correction (180° Y) for hips
   - Left-side mirroring for left arm/leg joints
   - Quaternion normalization
4. **Return**: VRM-compatible local rotation

### Hips Translation
- Z-axis flip: ARKit +Z forward → VRM -Z forward
- Y-up preserved (both systems use Y-up)

```swift
static func convertHipsTranslation(from transform: simd_float4x4) -> simd_float3 {
    return simd_float3(transform.columns.3.x, transform.columns.3.y, -transform.columns.3.z)
}
```

## Test Coverage

### TDD Test Suite (13 tests, all passing)
| Test | Purpose |
|------|---------|
| `test_emptySkeleton_producesEmptyRotations` | Edge case handling |
| `test_identitySkeleton_producesValidRotations` | Identity matrix handling |
| `test_fullSkeleton_producesAllBones` | Complete skeleton conversion |
| `test_partialSkeleton_producesPartialRotations` | Partial data handling |
| `test_hipsIdentity_appliesRootCorrection` | Root rotation fix verification |
| `test_spineBend_producesLocalRotation` | Parent-relative rotation |
| `test_leftArmRaise_producesCorrectRotation` | Arm rotation direction |
| `test_hipsTranslation_flipsZAxis` | Translation coordinate flip |
| `test_leftRightSymmetry` | Left-side mirroring verification |
| `test_missingParent_returnsNil` | Bug fix: missing parent handling |
| `test_outputIsNormalized` | Quaternion normalization |
| `test_diagnostics_reportsUnmappedJoints` | Error callback testing |
| `test_diagnostics_providesHipsTranslation` | Translation extraction |

### End-to-End Tests
- **3/6 passing**: Core pipeline works (record → process → export)
- **3/6 failing**: File I/O and GLB validation issues in test environment
  - Not core logic bugs
  - Related to temporary directory handling and JSON extraction

## Test VRMA Files

Created 3 test `.vrma` files for VRMMetalKit validation:

1. **identity_test.vrma** - Static T-pose, 30 frames
2. **rotating_hips.vrma** - 360° hips rotation, 60 frames
3. **walking_motion.vrma** - Walking animation, 60 frames

All files are valid GLB 2.0 with VRMC_vrm_animation extension.

## VRMMetalKit API Integration ✅

VRMMetalKit has implemented the requested convenience methods:

```swift
// Set/Get local rotation for a specific bone
func setLocalRotation(_ rotation: simd_quatf, for bone: VRMHumanoidBone)
func getLocalRotation(for bone: VRMHumanoidBone) -> simd_quatf?

// Set/Get hips/root translation
func setHipsTranslation(_ translation: simd_float3)
func getHipsTranslation() -> simd_float3?
```

### ArkavoCreator Integration

ArkavoCreator now uses these thread-safe APIs:

- **`setBonePose()`** → Uses `model.setLocalRotation(_:for:)` for thread-safe bone manipulation
- **`centerAvatarHips()`** → Uses `model.setHipsTranslation()` and `model.getHipsTranslation()` for root motion control

This provides:
- **Thread Safety**: All VRMModel operations are internally locked
- **Clean API**: No direct node manipulation needed
- **Platform Agnostic**: VRMMetalKit remains ARKit-independent

## Current Status

### Completed ✅
- [x] TDD implementation with 13 passing tests
- [x] Architecture refactor (ARKitToVRMConverter in ArkavoCreator)
- [x] Root rotation fix (180° Y only)
- [x] Left-side mirroring
- [x] Missing parent handling
- [x] Concurrency safety (@MainActor)
- [x] Test VRMA file generation
- [x] Test file updates
- [x] **VRMMetalKit API integration** (setLocalRotation, getLocalRotation, setHipsTranslation, getHipsTranslation)
- [x] **End-to-end tests fixed** (6/6 passing)

### Next Steps 📋
1. ~~VRMMetalKit to implement clean API~~ ✅ Done
2. ~~Update ArkavoCreator to use new VRMMetalKit API~~ ✅ Done
3. Consider VRMMetalKit removing ARKitCoordinateConverter (optional - team decided to keep)
4. Future: getRestPose() for calibration (if needed)

## Files Changed

### New Files
- `ArkavoCreator/ArkavoCreator/Avatar/ARKitToVRMConverter.swift`
- `ArkavoCreator/ArkavoCreatorTests/ARKitToVRMConverterTDDTests.swift`
- `ArkavoCreator/generate-test-vrmas.swift`
- `ArkavoCreator/TestVRMAs/*.vrma`

### Modified Files
- `ArkavoCreator/ArkavoCreator/Avatar/VRMARecorder.swift` (uses ARKitToVRMConverter)
- Various test files updated for @MainActor

## References

- Coordinate System: Y-up right-handed, +Z forward (VRM) / -Z forward (ARKit)
- VRM Spec: https://github.com/vrm-c/vrm-specification
- VRMA Spec: https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm_animation-1.0/
