# Remote Camera Streaming (Arkavo iOS → ArkavoCreator macOS)

This guide explains how to route live video plus ARKit metadata from an iPhone/iPad running the Arkavo app into ArkavoCreator on macOS. The feature currently targets local networks (Wi-Fi or USB network bridge) and uses a lightweight TCP protocol (NDJSON with `RemoteCameraMessage` payloads).

## Requirements

- ArkavoCreator (macOS) built from the `feature/continuity-multicamera` branch.
- Arkavo (iOS) from the same branch, running on a device that supports the chosen ARKit mode:
  - `ARFaceTrackingConfiguration`: iPhone/iPad with TrueDepth.
  - `ARBodyTrackingConfiguration`: A12 or newer devices.
- Both devices reachable over the same LAN or via USB with network tethering enabled.

## Mac Setup (ArkavoCreator)

1. Launch ArkavoCreator and open **Record**.
2. Ensure **Allow Remote Cameras** is enabled (on by default).
3. Note the displayed **Host** and **Port** values (defaults to your Mac’s hostname and port `5757`).
4. Optional: toggle local “Camera Sources” to include/discard built-in cameras; remote sources will appear in a separate list once connected.

## iOS Setup (Arkavo App)

1. Open Arkavo and tap **Create** to show the recording UI.
2. In the new **Stream to ArkavoCreator** card you can now:
   - Tap any entry under **Nearby Macs** (Bonjour auto-discovery) to auto-fill the host/port.
   - Or tap **Scan via NFC** to read an ArkavoCreator pairing tag and fill the connection info.
   - Manually override the fields if needed.
   - Choose **Face** or **Body** tracking before streaming.
3. Tap **Start Remote Camera**. You should see the status switch to *Streaming*.
4. The device immediately begins sending:
   - JPEG-encoded video frames (~15 FPS).
   - `CameraMetadataEvent` data (AR face blendshapes or body joints).

## Selecting the Remote Feed on macOS

1. In ArkavoCreator’s **Remote iOS Cameras** list, the device ID (e.g., `Paul_iPhone-face`) appears once the stream is detected.
2. Enable the toggle to include it in the PiP composition. It counts toward the multi-camera limit (max 4).
3. The remote feed can be combined with local cameras and will publish metadata to the avatar/VRM pipeline automatically.

## Notes & Troubleshooting

- The current protocol is unencrypted; keep streaming on trusted local networks until One-Time TDF + DTLS is layered in.
- If the Mac can’t resolve the hostname, enter the IP manually (find under iOS Settings → Wi-Fi → tap the `(i)` next to the network).
- ARKit tracking requires adequate lighting; the status text on iOS will report tracking errors.
- Remote metadata is posted through `Notification.Name.cameraMetadataUpdated`, so avatar rigs respond exactly like Continuity Camera face feed data.

## Implementation Status (Nov 2025)

### ✅ Completed Features

**Multi-Layered Discovery**
- ✅ Bonjour/mDNS auto-discovery (NetServiceBrowser)
- ✅ Network framework discovery (NWBrowser) for peer-to-peer
- ✅ QR code quick connect (`arkavo://connect?host=...&port=...`)
- ✅ Auto-connect on app launch (configurable via UserDefaults)
- ✅ Connection caching for faster reconnect

**Permissions & Privacy**
- ✅ Local network permission (`NSLocalNetworkUsageDescription`)
- ✅ Microphone permission (`NSMicrophoneUsageDescription`)
- ✅ Camera permission (`NSCameraUsageDescription`)
- ✅ Bonjour service declaration (`NSBonjourServices: _arkavo-remote._tcp`)
- ✅ Graceful permission handling (prompts before ARKit start)

**Streaming**
- ✅ ARKit face tracking (52 blend shapes + head transform)
- ✅ JPEG frame streaming (~15 FPS)
- ✅ Audio capture (microphone enabled)
- ✅ NDJSON protocol with handshake, frame, metadata, audio messages
- ✅ Dynamic port assignment (Mac server auto-assigns available port)

**Avatar Integration**
- ✅ VRMMetalKit 0.3.1 with ARKitFaceDriver
- ✅ Metadata forwarding via NotificationCenter
- ✅ Multi-source face tracking support (ARFaceSource infrastructure)
- ✅ Camera positioning optimized for face framing (eye-level at Y=1.45)

**UX Improvements**
- ✅ QR code display in ArkavoCreator UI
- ✅ Connection status indicators
- ✅ Dual discovery systems for redundancy
- ✅ Enhanced logging and diagnostics

### 📋 Next Steps

- Encrypt the transport using One-Time TDF session keys
- Support high-bitrate HEVC streaming with hardware encode/decode for lower latency
- Implement NFC pairing for one-tap connection
