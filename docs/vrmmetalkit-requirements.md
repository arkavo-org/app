# VRMMetalKit Requirements for Continuity Multi‑Camera Support

## Context
ArkavoCreator (macOS) now consumes remote iPhone/iPad camera feeds that deliver both video and ARKit metadata via `CameraMetadataEvent`s coming from `ArkavoRecorder`. The VRM avatar stack (`VRMAvatarRenderer` + VRMMetalKit) is the consumer of those semantic signals. To fully unlock Continuity-style multi-camera capture (USB-C, Wi-Fi, NFC pairing) we need specific capabilities from the VRMMetalKit package that lives at `/Users/paul/Projects/arkavo/VRMMetalKit`.

## Goals
- Drive VRM avatars with low-latency ARKit face and body tracking data originating from remote devices.
- Support multiple simultaneous cameras/metadata sources, including Continuity Camera (video-only) and Arkavo remote AR rigs.
- Maintain renderer performance targets (60 fps compositing) while adding smoothing, filtering, and testing hooks for QA.

## Functional Requirements
1. **Face Tracking Bridge**
   - Provide a first-class API that ingests ARKit-style blend shapes (string keys such as `eyeBlinkLeft`, `jawOpen`, etc.) and maps them onto `VRMExpressionPreset`s.
   - Include configurable smoothing/latency controls (EMA, Kalman, windowed averaging) so ArkavoCreator can tune responsiveness per scene.
   - Expose presets/mappings as data so Arkavo teams can patch them without rebuilding VRMMetalKit.

2. **Body Tracking Integration**
   - Define a data model that accepts ARKit `ARSkeleton3D` joint transforms (or equivalent) and retargets them to the VRM humanoid rig.
   - Support partial skeleton updates (upper body only) and gracefully degrade when joints are missing.
   - Surface errors/status codes so ArkavoCreator can message “Body feed unavailable” without crashing.

3. **Multi-Source Handling**
   - Allow multiple simultaneous metadata sources (e.g., face rig + separate body rig). Provide APIs to prioritize/merge feeds or switch sources live.
   - Ensure internal state (expression weights, animation players) can be sandboxed per source to avoid cross-talk between avatars.

4. **Transport-Aware QoS**
   - Accept timestamps with metadata events and account for jitter (e.g., interpolate or drop late frames).
   - Provide hooks to pause/resume expression updates when metadata is stale (>150 ms) to avoid avatar popping.

5. **Testing & Instrumentation**
   - Ship sample harnesses/tests that replay recorded metadata traces (face/body) so we can regression-test without live devices.
   - Add logging/metrics toggles that emit per-expression weights and retargeted bone deltas for debugging; log routing should be opt-in to avoid perf hits in production.

6. **Extensibility**
   - Keep the API surface transport-agnostic: treat CameraMetadata payloads as structs so future modalities (gaze vectors, visemes, custom gestures) can plug in.
   - Document how external teams can contribute new expression mappings or body-solvers without forking the renderer.

## Non-Functional Requirements
- **Performance:** Maintain current frame budgets (<16 ms per frame on M3 Pro) even when applying blendshape smoothing and skeleton retargeting.
- **Threading:** APIs must be safe to call from ArkavoCreator’s `@MainActor` contexts. Provide explicit `Sendable` annotations where work can be offloaded.
- **Backward Compatibility:** Existing VRM users without AR metadata should continue to work with no API changes; new features must be additive.

## Deliverables
1. API spec / Swift interfaces for the face and body metadata consumers.
2. Implementation plan outlining how VRMMetalKit will retarget ARKit joints to VRM humanoids (including fallback strategies).
3. Test harness + sample metadata recordings for CI.
4. Documentation in `README.md` (or a dedicated guide) explaining how ArkavoCreator should integrate the new APIs.

Please let us know if additional background from the ArkavoCreator side is needed; we can provide sample `CameraMetadataEvent` payloads or live capture traces once the interfaces are defined.
