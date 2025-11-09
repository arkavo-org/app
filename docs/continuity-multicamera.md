# Continuity Multi-Camera & ARKit Capture Plan

## Goal
Allow ArkavoCreator (macOS) to drive ArkavoRecorder sessions using external iOS devices (iPhone/iPad) as intelligent cameras that stream both video and ARKit-derived metadata (face/body). This bridges gaps where mac hardware lacks TrueDepth sensors while still supporting Continuity Camera-level UX plus hardwired USB-C and local wireless transports.

## Current State
- `RecordingSession` can accept external camera metadata via `updateCameraMetadata(_:)` and fan out updates through an optional `metadataHandler`, which ArkavoCreator now uses to update avatar rigs in real-time.
- `CameraMetadata`/`ARFaceMetadata` describe payloads generically so that additional semantic streams (body joints, LiDAR depth, custom signals) can be added without reworking the encoder.
- `ARKitCaptureManager` (ArkavoRecorder) wraps `ARFaceTrackingConfiguration` and `ARBodyTrackingConfiguration`, exposing a delegate that receives CVPixelBuffers plus semantic annotations. The helper is compiled only for iOS/macCatalyst builds with ARKit availability.
- `VRMAvatarRenderer` consumes normalized `[String: Float]` blendshapes instead of `ARFaceAnchor.BlendShapeLocation` so data may arrive from any transport.

## Proposed Architecture
1. **Remote Capture Service (Arkavo iOS app):**
   - Embed `ARKitCaptureManager` alongside the existing `CameraManager` feed.
   - Offer a lightweight UI that lets operators pick Face vs Body tracking and transport (USB-C tether, Wi-Fi LAN, NFC bootstrapped Wi-Fi Direct).
   - Produce a combined payload: encoded video frames (H.265 preferred) plus `CameraMetadataEvent`s serialized via FlatBuffers (reusing `ArkavoStreaming`).

2. **Transport Layer:**
   - **USB-C:** use `usbmuxd`/`Network.framework` to open a TCP listener on-device, advertising via Bonjour. Provides lowest latency for studio rigs.
   - **Wi-Fi LAN:** rely on `ArkavoStreaming` P2P channel with DTLS encryption; discovery via Bonjour + fallback to QR handshake.
   - **NFC tap:** optional bootstrap exchanging ephemeral keys + target IP for faster Wi-Fi pairing.
   - Each transport shares the same message schema so Creator can treat them uniformly.

3. **Creator Ingest (macOS):**
   - Extend `CameraManager` with a `remote` transport case that renders incoming frames into `latestCameraBuffers` without needing local `AVCaptureDevice`s.
   - When a remote stream connects, register its identifier with `RecordingSession.setCameraSources` and call `updateCameraMetadata` whenever metadata packets arrive.
   - Expose UI affordances in `RecordView` so producers can select remote devices, monitor link quality, and pick whether to drive the avatar rig, PiP tile, or both.

4. **Metadata Semantics:**
   - **Face:** already mapped via `[String: Float]` blend shapes to avatar expressions.
   - **Body:** extend `CameraMetadata` with `.arBody(ARBodyMetadata)` (skeleton joint transforms) so Creator can feed motion capture rigs or analytics dashboards.
   - **Custom:** keep `.custom(name:payload:)` for experimental channels (e.g., gaze, lip sync visemes).

5. **Studio Display / mac Input:**
   - Macs without TrueDepth sensors request AR metadata from any paired iOS stream. When Continuity Camera alone is active, we still get high-res video but no AR metadata—UI should surface a badge (“Video-only”).
   - If user connects both Continuity and Arkavo Remote AR feed, RecordingSession can composite Continuity as PiP while the avatar uses AR metadata.

## Implementation Steps
1. **iOS Companion Work (Arkavo app):**
   - Add a `RemoteCameraController` that owns `ARKitCaptureManager`, handles permission prompts, and surfaces its delegate callbacks as `AsyncSequence`s.
   - Serialize `ARKitFrameMetadata` into `CameraMetadataEvent`s (face/body) and attach them to outgoing frame packets.
   - Support capture presets for 1080p@30 and 4K@30 with exposure controls matching Creator.

2. **Streaming Protocol:**
   - Define FlatBuffer schema for `CameraMetadataEvent` (source id, timestamp, payload union) under `ArkavoStreaming`.
   - Extend `RecordingSession` networking handshake to treat remote cameras as sources with lifecycle events (connect, heartbeat, disconnect).
   - Encrypt channels using existing One-Time TDF key rotation; metadata piggybacks on the same symmetric stream.

3. **Creator UI/UX:**
   - `RecordViewModel` tracks remote availability, surfaces them in `RecordView` pickers, and shows per-source health + transport type.
   - Provide quick actions to trigger AR mode (face/body) on remote devices via control channel messages so producers can reconfigure without touching the phone.
   - Integrate avatar/metadata previews so artists can verify blendshape signals before rolling.

4. **Testing & Tooling:**
   - Add unit tests covering `CameraMetadata` serialization/deserialization plus renderer blendshape mappings.
   - Build instrumentation in `automation/` to spin up simulators + Continuity Camera stand-ins, validating multi-source composition.
   - Capture reference recordings (video + metadata logs) into `test_results/continuity/` for regressions.

## Open Questions / Next Steps
- Decide whether remote video is composited on-device (H.265) vs raw CVPixelBuffer streaming. H.265 lowers bandwidth but adds encode latency.
- Determine pairing UX order: NFC tap ➜ Wi-Fi Direct vs scanning QR codes for LAN endpoints.
- Align on how body-tracking data drives downstream avatars (VRM humanoid vs Unreal bridge) before finalizing metadata schema.

This plan gets ARKit data flowing from iOS/iPadOS hardware into ArkavoCreator recordings while keeping transport-agnostic plumbing inside ArkavoRecorder.
