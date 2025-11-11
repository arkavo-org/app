# Twitch Streaming Integration - Manual Test Plan

**Version:** 1.0
**Last Updated:** 2025-11-10
**Platform:** ArkavoCreator (iOS 26, iPadOS 26, macOS 26)
**Test Type:** Manual Testing with Live Twitch Services

---

## Table of Contents
1. [Prerequisites & Setup](#prerequisites--setup)
2. [OAuth Authentication Tests](#oauth-authentication-tests)
3. [RTMP Streaming Tests](#rtmp-streaming-tests)
4. [Video/Audio Encoding Tests](#videoaudio-encoding-tests)
5. [Error Scenario Tests](#error-scenario-tests)
6. [End-to-End Workflow Tests](#end-to-end-workflow-tests)
7. [Test Execution Tracking](#test-execution-tracking)
8. [Bug Reporting Template](#bug-reporting-template)

---

## Prerequisites & Setup

### Test Environment Configuration

**Required Hardware:**
- [ ] Mac running macOS 26 OR iPad/iPhone running iOS/iPadOS 26
- [ ] Active internet connection (minimum 10 Mbps upload)
- [ ] Camera (for camera capture testing)
- [ ] Microphone (for audio testing)

**Required Twitch Setup:**
- [ ] Test Twitch account created (separate from production account)
- [ ] Account verified and eligible for streaming
- [ ] Stream key retrieved from: https://dashboard.twitch.tv/settings/stream
- [ ] OAuth Client ID confirmed: `icvk7xc2gsgcx1fjtu6tjvn1olvjjk`

**Required App Permissions:**
- [ ] Screen Recording permission granted
- [ ] Camera access permission granted
- [ ] Microphone access permission granted
- [ ] Network access enabled

**Test Data Preparation:**
```
Test Twitch Account Username: ___________________
Test Twitch Account Email: ___________________
Test Stream Key: ___________________
OAuth Redirect URI: https://webauthn.arkavo.net/oauth/arkavocreator/twitch
```

**Verification Checklist:**
- [ ] ArkavoCreator app built and installed
- [ ] App launches without errors
- [ ] All system permissions granted
- [ ] Network connectivity verified
- [ ] Test credentials documented

---

## OAuth Authentication Tests

### Test Category: OAuth Flow - Happy Path

#### **TEST-AUTH-001: First-Time Twitch Login**
**Priority:** P0 (Critical)
**Preconditions:** User not logged into Twitch, no stored credentials

**Steps:**
1. Launch ArkavoCreator app
2. Navigate to Dashboard (ContentView)
3. Verify "Login with Twitch" button is visible
4. Click "Login with Twitch" button
5. Observe WebView opens with Twitch authorization page
6. Enter test Twitch credentials (username/password)
7. Authorize the application
8. Observe redirect to `arkavocreator://oauth/twitch`

**Expected Results:**
- [ ] WebView opens showing Twitch login page
- [ ] URL contains correct client_id and redirect_uri
- [ ] After authorization, WebView closes automatically
- [ ] Dashboard shows Twitch username
- [ ] "Login with Twitch" button changes to "Logout" or shows logged-in state
- [ ] No error messages displayed
- [ ] User info persists across app restarts

**Pass Criteria:** User successfully authenticates and username displays in UI

---

#### **TEST-AUTH-002: Token Exchange Verification**
**Priority:** P0 (Critical)
**Preconditions:** OAuth callback received with authorization code

**Steps:**
1. Complete TEST-AUTH-001 steps 1-8
2. Monitor network traffic or logs for token exchange
3. Verify access token received
4. Navigate to Stream tab
5. Select "Twitch" platform

**Expected Results:**
- [ ] Token exchange request sent to `https://id.twitch.tv/oauth2/token`
- [ ] Access token received and stored
- [ ] No "notAuthenticated" errors in logs
- [ ] Stream key field is available for input
- [ ] User remains authenticated

**Pass Criteria:** Access token successfully retrieved and stored

---

#### **TEST-AUTH-003: User Info Retrieval**
**Priority:** P1 (High)
**Preconditions:** Access token obtained from TEST-AUTH-002

**Steps:**
1. Complete successful login (TEST-AUTH-001)
2. Check Dashboard for user information display
3. Verify username matches test account
4. Check logs for Helix API call to `/users`

**Expected Results:**
- [ ] User info API call to `https://api.twitch.tv/helix/users` succeeds
- [ ] Correct username displayed in UI
- [ ] User ID stored internally (check UserDefaults or logs)
- [ ] No API errors in logs

**Pass Criteria:** Correct username and user ID retrieved and displayed

---

#### **TEST-AUTH-004: Token Persistence**
**Priority:** P1 (High)
**Preconditions:** User successfully logged in

**Steps:**
1. Complete successful login (TEST-AUTH-001)
2. Verify username displayed in Dashboard
3. Force quit ArkavoCreator app completely
4. Relaunch app
5. Check Dashboard login status

**Expected Results:**
- [ ] User remains logged in after app restart
- [ ] Username displayed without re-login
- [ ] Access token loaded from storage (UserDefaults)
- [ ] No authentication errors on app launch

**Pass Criteria:** User session persists across app restarts

---

#### **TEST-AUTH-005: Logout Functionality**
**Priority:** P1 (High)
**Preconditions:** User successfully logged in

**Steps:**
1. Complete successful login (TEST-AUTH-001)
2. Navigate to Dashboard
3. Click "Logout" button (if available) or find logout option
4. Confirm logout action
5. Verify UI returns to logged-out state

**Expected Results:**
- [ ] Logout action clears stored access token
- [ ] UI returns to showing "Login with Twitch" button
- [ ] Username no longer displayed
- [ ] Stream key remains in Keychain (user data preserved)
- [ ] App restart requires re-login

**Pass Criteria:** User successfully logs out and session is cleared

---

### Test Category: OAuth Flow - Error Scenarios

#### **TEST-AUTH-006: OAuth Callback Error Handling**
**Priority:** P1 (High)
**Preconditions:** User initiates login

**Steps:**
1. Start login flow (TEST-AUTH-001 steps 1-4)
2. In WebView, deny authorization or click "Cancel"
3. Observe app behavior

**Expected Results:**
- [ ] Error message displayed to user
- [ ] Error type: `TwitchError.authorizationFailed` in logs
- [ ] User remains logged out
- [ ] UI returns to stable state (can retry login)
- [ ] No app crash

**Pass Criteria:** App gracefully handles authorization denial

---

#### **TEST-AUTH-007: Invalid Callback URL**
**Priority:** P2 (Medium)
**Preconditions:** Test with malformed callback (requires code modification or proxy)

**Steps:**
1. Simulate callback with missing auth code: `arkavocreator://oauth/twitch`
2. Observe error handling

**Expected Results:**
- [ ] Error: `TwitchError.noAuthCode` caught
- [ ] User-friendly error message displayed
- [ ] No app crash
- [ ] User can retry login

**Pass Criteria:** Invalid callbacks handled without crash

---

#### **TEST-AUTH-008: Network Failure During Token Exchange**
**Priority:** P1 (High)
**Preconditions:** User completes OAuth authorization

**Steps:**
1. Start login flow (TEST-AUTH-001 steps 1-7)
2. Disable network connection immediately after authorization
3. Observe token exchange failure

**Expected Results:**
- [ ] Error: `TwitchError.tokenExchangeFailed` or network error
- [ ] User notified of network issue
- [ ] Can retry login when network restored
- [ ] No partial/corrupt token stored

**Pass Criteria:** Network failure handled gracefully with retry option

---

#### **TEST-AUTH-009: Expired Token Handling**
**Priority:** P2 (Medium)
**Preconditions:** User logged in with old/expired token

**Steps:**
1. Log in successfully
2. Manually expire token (wait or invalidate via Twitch dashboard)
3. Attempt to use Twitch features (stream setup)
4. Observe error handling

**Expected Results:**
- [ ] API calls fail with authentication error
- [ ] User prompted to re-login
- [ ] Error message indicates expired session
- [ ] Re-login succeeds and restores functionality

**Pass Criteria:** Expired tokens detected and user prompted to re-authenticate

**Note:** Current implementation may not detect expiration gracefully - this is a known gap to test and document.

---

#### **TEST-AUTH-010: Invalid Client ID/Configuration**
**Priority:** P2 (Medium)
**Preconditions:** OAuth configuration with invalid client ID (test environment)

**Steps:**
1. Modify `Secrets.swift` to use invalid client ID (testing only)
2. Attempt login
3. Observe Twitch response

**Expected Results:**
- [ ] Twitch returns "invalid_client" error
- [ ] Error message displayed to user
- [ ] App doesn't crash
- [ ] Logs show authorization failure

**Pass Criteria:** Invalid configuration fails safely with clear error

**Note:** Restore valid client ID after test

---

#### **TEST-AUTH-011: WebView Dismissal During Login**
**Priority:** P2 (Medium)
**Preconditions:** User initiates login

**Steps:**
1. Click "Login with Twitch"
2. WebView opens
3. Close WebView window before completing login (if dismissible)
4. Observe app state

**Expected Results:**
- [ ] Login cancelled gracefully
- [ ] User remains logged out
- [ ] No error message (or "Login cancelled")
- [ ] Can retry login

**Pass Criteria:** Manual dismissal doesn't leave app in bad state

---

#### **TEST-AUTH-012: Concurrent Login Attempts**
**Priority:** P3 (Low)
**Preconditions:** None

**Steps:**
1. Click "Login with Twitch" button rapidly multiple times
2. Observe if multiple WebViews open
3. Complete one login flow

**Expected Results:**
- [ ] Only one WebView opens OR subsequent clicks ignored
- [ ] No duplicate token exchanges
- [ ] Login succeeds normally
- [ ] No app crash or UI glitches

**Pass Criteria:** Concurrent attempts handled safely

---

## RTMP Streaming Tests

### Test Category: RTMP Connection - Happy Path

#### **TEST-RTMP-001: RTMP Server Connection**
**Priority:** P0 (Critical)
**Preconditions:** User logged in, stream key entered, recording session active

**Steps:**
1. Navigate to Stream tab
2. Select "Twitch" platform
3. Enter valid stream key in SecureField
4. Start a recording session (prerequisite for streaming)
5. Click "Start Stream" button
6. Monitor connection status

**Expected Results:**
- [ ] Status shows "📡 Connecting to RTMP..."
- [ ] TCP connection established to `live.twitch.tv:1935`
- [ ] Status updates to "🤝 Performing RTMP handshake..."
- [ ] Handshake completes: "✅ RTMP handshake complete"
- [ ] Publishing starts: "✅ RTMP publishing started"
- [ ] Stream goes live on Twitch (verify at dashboard.twitch.tv)

**Pass Criteria:** Stream successfully connects and goes live on Twitch

**Files Referenced:**
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/RTMPPublisher.swift:56 (connect)
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/RTMPPublisher.swift:126 (handshake)

---

#### **TEST-RTMP-002: RTMP Handshake Verification**
**Priority:** P0 (Critical)
**Preconditions:** TCP connection established to Twitch RTMP server

**Steps:**
1. Complete TEST-RTMP-001 steps 1-5
2. Monitor logs during handshake phase
3. Verify handshake sequence: C0/C1 → S0/S1/S2 → C2

**Expected Results:**
- [ ] Handshake log shows "🤝 Performing RTMP handshake..."
- [ ] C0/C1 packets sent (1537 bytes total)
- [ ] S0/S1/S2 packets received (3073 bytes total)
- [ ] C2 packet sent in response
- [ ] Handshake completes without errors
- [ ] Connection ready for RTMP commands

**Pass Criteria:** Full RTMP handshake completes successfully

---

#### **TEST-RTMP-003: RTMP Publish Command**
**Priority:** P0 (Critical)
**Preconditions:** RTMP handshake complete

**Steps:**
1. Complete TEST-RTMP-002 (handshake)
2. Observe publish command sequence in logs
3. Verify stream appears as "Live" in Twitch dashboard

**Expected Results:**
- [ ] Connect command sent with app="live"
- [ ] ReleaseStream command sent with stream key
- [ ] FCPublish command sent
- [ ] CreateStream command sent
- [ ] Publish command sent with stream key
- [ ] Stream shows as "Live" in Twitch dashboard within 10 seconds
- [ ] Status: "✅ RTMP publishing started"

**Pass Criteria:** Publish command sequence executes and stream goes live

**Files Referenced:**
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/AMF.swift:42 (connect)
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/AMF.swift:74 (publish)

---

#### **TEST-RTMP-004: Stream Statistics Monitoring**
**Priority:** P1 (High)
**Preconditions:** Stream actively publishing to Twitch

**Steps:**
1. Complete TEST-RTMP-003 (stream live)
2. Observe statistics in StreamView UI
3. Monitor for 60 seconds
4. Record statistics values

**Expected Results:**
- [ ] Duration counter increases (format: MM:SS)
- [ ] Bitrate displays and fluctuates (target ~5 Mbps for 1080p)
- [ ] FPS shows ~30 (matches encoding setting)
- [ ] Frames sent counter increases continuously
- [ ] Data sent increases (MB)
- [ ] Statistics update every second
- [ ] Values are reasonable and consistent

**Pass Criteria:** All statistics display accurate, real-time values

**Files Referenced:**
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/RTMPPublisher.swift:267 (statistics)
- ArkavoCreator/ArkavoCreator/StreamView.swift:89 (UI display)

---

#### **TEST-RTMP-005: Stream Stop and Cleanup**
**Priority:** P0 (Critical)
**Preconditions:** Stream actively publishing

**Steps:**
1. Complete TEST-RTMP-004 (stream running)
2. Click "Stop Stream" button
3. Verify stream stops on Twitch dashboard
4. Check app state

**Expected Results:**
- [ ] "Stop Stream" button immediately disables
- [ ] Stream status changes from "Live" to stopped
- [ ] RTMP connection closes gracefully
- [ ] Statistics freeze at final values
- [ ] Twitch dashboard shows stream as offline within 10 seconds
- [ ] Can restart stream without app restart

**Pass Criteria:** Stream stops cleanly, connection closed, ready to restart

---

### Test Category: RTMP Connection - Error Scenarios

#### **TEST-RTMP-006: Invalid Stream Key**
**Priority:** P0 (Critical)
**Preconditions:** User logged in, recording active

**Steps:**
1. Navigate to Stream tab
2. Enter invalid/fake stream key: "invalid_stream_key_12345"
3. Click "Start Stream"
4. Observe error handling

**Expected Results:**
- [ ] Connection establishes to Twitch RTMP server
- [ ] Handshake completes
- [ ] Publish command sent
- [ ] Twitch rejects publish (expect error from server)
- [ ] Error message displayed to user
- [ ] Stream does NOT go live
- [ ] User can correct stream key and retry

**Pass Criteria:** Invalid stream key rejected with clear error message

**Note:** Twitch may not send explicit rejection - test if stream goes live to verify

---

#### **TEST-RTMP-007: Network Interruption During Streaming**
**Priority:** P1 (High)
**Preconditions:** Stream actively publishing

**Steps:**
1. Start streaming successfully (TEST-RTMP-003)
2. Stream for 30 seconds
3. Disable network connection (Wi-Fi off)
4. Wait 10 seconds
5. Re-enable network connection
6. Observe recovery behavior

**Expected Results:**
- [ ] TCP connection failure detected
- [ ] Error displayed to user
- [ ] Stream status shows disconnected
- [ ] Stream does NOT automatically reconnect (current limitation)
- [ ] User must manually restart stream
- [ ] Restart succeeds after network restored

**Pass Criteria:** Network failure detected, user can manually recover

**Known Limitation:** No automatic retry logic - document this behavior

**Files Referenced:**
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/RTMPPublisher.swift:173 (receive)

---

#### **TEST-RTMP-008: Connection Timeout**
**Priority:** P2 (Medium)
**Preconditions:** Slow or unstable network

**Steps:**
1. Simulate slow network (if possible) or use throttled connection
2. Attempt to start stream
3. Monitor connection timeout behavior

**Expected Results:**
- [ ] Connection attempt times out if server unreachable
- [ ] Timeout error displayed (not indefinite hang)
- [ ] User can retry connection
- [ ] App remains responsive during timeout

**Pass Criteria:** Connection timeout handled gracefully

**Note:** Current implementation may not have explicit timeout - test and document

---

#### **TEST-RTMP-009: Server Unreachable**
**Priority:** P1 (High)
**Preconditions:** Invalid RTMP server URL (use Custom RTMP mode)

**Steps:**
1. Select "Custom RTMP" platform
2. Enter invalid URL: `rtmp://invalid.server.example.com/app`
3. Enter any stream key
4. Click "Start Stream"

**Expected Results:**
- [ ] DNS resolution fails OR connection refused
- [ ] Error: `RTMPError.connectionFailed` thrown
- [ ] Error message displayed to user
- [ ] No indefinite hang
- [ ] User can correct URL and retry

**Pass Criteria:** Unreachable server fails quickly with clear error

---

#### **TEST-RTMP-010: Streaming Without Active Recording**
**Priority:** P1 (High)
**Preconditions:** No recording session active

**Steps:**
1. Ensure no recording is active (stop any recordings)
2. Navigate to Stream tab
3. Select Twitch, enter stream key
4. Click "Start Stream"

**Expected Results:**
- [ ] Error message: "No active recording session"
- [ ] Stream does NOT start
- [ ] User prompted to start recording first
- [ ] No crash

**Pass Criteria:** Cannot start stream without recording session

**Files Referenced:**
- ArkavoCreator/ArkavoCreator/StreamViewModel.swift:60 (validation)

---

#### **TEST-RTMP-011: Concurrent Stream Attempts**
**Priority:** P2 (Medium)
**Preconditions:** Stream already publishing

**Steps:**
1. Start streaming successfully (TEST-RTMP-003)
2. While stream active, click "Start Stream" again (if button enabled)
3. Or attempt to start second stream to different platform

**Expected Results:**
- [ ] Second stream attempt rejected OR button disabled
- [ ] Error message displayed
- [ ] First stream continues uninterrupted
- [ ] No app crash or connection corruption

**Pass Criteria:** Cannot start duplicate streams simultaneously

---

#### **TEST-RTMP-012: Handshake Failure**
**Priority:** P2 (Medium)
**Preconditions:** Simulate handshake failure (difficult without proxy/mock)

**Steps:**
1. Attempt to connect to RTMP server
2. If handshake fails, observe error handling

**Expected Results:**
- [ ] Error: `RTMPError.handshakeFailed` thrown
- [ ] Connection closed
- [ ] Error displayed to user
- [ ] Can retry connection

**Pass Criteria:** Handshake failure handled gracefully

**Note:** Difficult to trigger naturally - may require code modification or proxy

---

#### **TEST-RTMP-013: Large Buffer/Memory Test**
**Priority:** P2 (Medium)
**Preconditions:** None

**Steps:**
1. Start streaming successfully
2. Stream continuously for 30 minutes
3. Monitor app memory usage
4. Observe statistics and performance

**Expected Results:**
- [ ] Memory usage remains stable (no leak)
- [ ] Stream quality consistent throughout
- [ ] Statistics accurate after 30 minutes
- [ ] No app crash or slowdown
- [ ] Stream stops cleanly

**Pass Criteria:** Long-duration streaming stable without memory leak

---

#### **TEST-RTMP-014: Rapid Start/Stop Cycles**
**Priority:** P2 (Medium)
**Preconditions:** Recording session active

**Steps:**
1. Start stream
2. Immediately stop stream (within 2 seconds)
3. Repeat 10 times
4. Observe stability

**Expected Results:**
- [ ] Each start/stop cycle completes cleanly
- [ ] No connection errors accumulate
- [ ] No memory leaks
- [ ] App remains responsive
- [ ] Final stream works normally

**Pass Criteria:** Rapid cycling doesn't cause instability

---

#### **TEST-RTMP-015: Stream Key with Special Characters**
**Priority:** P3 (Low)
**Preconditions:** None

**Steps:**
1. Enter stream key containing special characters (if Twitch provides one)
2. Attempt to start stream

**Expected Results:**
- [ ] Stream key accepted without encoding issues
- [ ] Stream publishes successfully
- [ ] No parsing or encoding errors

**Pass Criteria:** Special characters in stream key handled correctly

---

## Video/Audio Encoding Tests

### Test Category: Video Encoding Quality

#### **TEST-ENC-001: H.264 Video Encoding**
**Priority:** P0 (Critical)
**Preconditions:** Recording and streaming active

**Steps:**
1. Start recording session (screen + camera)
2. Start Twitch stream
3. Stream for 2 minutes
4. Watch live stream on Twitch (use second device or browser)
5. Stop stream
6. Review Twitch VOD

**Expected Results:**
- [ ] Video appears on Twitch stream within 10-15 seconds (latency)
- [ ] Resolution: 1920x1080 confirmed in Twitch player settings
- [ ] Frame rate: ~30 FPS smooth playback
- [ ] Bitrate: ~5 Mbps (check Twitch dashboard stats)
- [ ] No visible corruption or artifacts (reasonable compression)
- [ ] Screen content readable (text, UI elements)
- [ ] Camera feed clear and synchronized

**Pass Criteria:** Video quality acceptable for streaming, no major artifacts

**Files Referenced:**
- ArkavoKit/Sources/ArkavoRecorder/VideoEncoder.swift:24 (H.264 settings)
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/FLVMuxer.swift:50 (video tags)

---

#### **TEST-ENC-002: AAC Audio Encoding**
**Priority:** P0 (Critical)
**Preconditions:** Recording with audio enabled

**Steps:**
1. Enable microphone and system audio capture
2. Start recording and streaming
3. Play audio content (music, speech)
4. Watch live stream and verify audio
5. Check Twitch VOD

**Expected Results:**
- [ ] Audio present in Twitch stream
- [ ] Sample rate: 44.1 kHz or 48 kHz
- [ ] Bitrate: ~128 kbps
- [ ] Audio synchronized with video (no drift)
- [ ] No audio crackling or distortion
- [ ] Volume levels appropriate
- [ ] Both microphone and system audio captured (if enabled)

**Pass Criteria:** Audio quality clear, synchronized, no distortion

**Files Referenced:**
- ArkavoKit/Sources/ArkavoRecorder/VideoEncoder.swift:125 (audio settings)
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/FLVMuxer.swift:106 (audio tags)

---

#### **TEST-ENC-003: FLV Container Format**
**Priority:** P1 (High)
**Preconditions:** Stream actively publishing

**Steps:**
1. Start streaming
2. Verify Twitch accepts stream (no format errors)
3. Check for any Twitch playback errors
4. Verify stream metadata in Twitch dashboard

**Expected Results:**
- [ ] Twitch accepts FLV format without errors
- [ ] Video codec: H.264 (AVC) detected
- [ ] Audio codec: AAC detected
- [ ] Sequence headers sent before frames
- [ ] No "unsupported format" errors on Twitch
- [ ] Stream plays back normally

**Pass Criteria:** FLV format compatible with Twitch ingestion

**Files Referenced:**
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/FLVMuxer.swift:15 (FLV structure)

---

#### **TEST-ENC-004: Multi-Source Audio (Screen + Microphone)**
**Priority:** P1 (High)
**Preconditions:** Multiple audio sources available

**Steps:**
1. Enable screen recording audio
2. Enable microphone audio
3. Optionally enable camera audio
4. Start recording and streaming
5. Play system audio (music/video)
6. Speak into microphone
7. Verify mixed audio on Twitch stream

**Expected Results:**
- [ ] System audio captured and streamed
- [ ] Microphone audio captured and streamed
- [ ] Both audio sources mixed (not exclusive)
- [ ] Audio levels balanced
- [ ] No audio clipping or distortion
- [ ] Synchronized with video

**Pass Criteria:** Multiple audio sources properly mixed and streamed

**Files Referenced:**
- ArkavoKit/Sources/ArkavoRecorder/RecordingSession.swift:234 (multi-track audio)

---

#### **TEST-ENC-005: Frame Rate Validation**
**Priority:** P1 (High)
**Preconditions:** Stream active

**Steps:**
1. Start streaming
2. Monitor FPS in stream statistics (StreamView UI)
3. Watch Twitch stream and verify smoothness
4. Record statistics for 60 seconds

**Expected Results:**
- [ ] FPS statistic shows ~30 FPS consistently
- [ ] Actual frame rate on Twitch matches (verify in player)
- [ ] No frame dropping (stable FPS)
- [ ] Smooth motion in stream playback
- [ ] FPS doesn't degrade over time

**Pass Criteria:** Consistent 30 FPS maintained throughout stream

---

#### **TEST-ENC-006: Bitrate Validation**
**Priority:** P1 (High)
**Preconditions:** Stream active

**Steps:**
1. Start streaming
2. Monitor bitrate in stream statistics
3. Check Twitch dashboard for ingestion bitrate
4. Stream for 5 minutes
5. Record bitrate fluctuations

**Expected Results:**
- [ ] Bitrate displayed in UI (Kbps/Mbps)
- [ ] Average bitrate ~5 Mbps for 1080p30
- [ ] Bitrate fluctuates within reasonable range (4-6 Mbps)
- [ ] Twitch dashboard shows matching bitrate
- [ ] No excessive bitrate spikes or drops

**Pass Criteria:** Bitrate stable and appropriate for quality settings

---

#### **TEST-ENC-007: Screen Content Encoding**
**Priority:** P1 (High)
**Preconditions:** Screen recording enabled

**Steps:**
1. Display content with text, images, and motion
2. Start recording and streaming
3. View Twitch stream
4. Test various content types:
   - Static text (code, documents)
   - Fast motion (video playback, scrolling)
   - High detail images
   - UI elements

**Expected Results:**
- [ ] Text readable at source resolution
- [ ] Fast motion reasonably smooth (acceptable compression artifacts)
- [ ] High detail images recognizable
- [ ] UI elements clear
- [ ] Colors accurate
- [ ] No severe blocking artifacts

**Pass Criteria:** Screen content legible and recognizable on stream

---

#### **TEST-ENC-008: Camera Feed Encoding**
**Priority:** P1 (High)
**Preconditions:** Camera enabled in recording

**Steps:**
1. Enable camera capture
2. Position camera feed in frame
3. Start streaming
4. Move in front of camera
5. Verify camera feed on Twitch stream

**Expected Results:**
- [ ] Camera feed visible in stream
- [ ] Camera positioned correctly (matches preview)
- [ ] Camera feed synchronized with screen content
- [ ] Reasonable video quality for camera
- [ ] No camera feed corruption

**Pass Criteria:** Camera feed properly encoded and visible on stream

---

#### **TEST-ENC-009: Encoding Performance Under Load**
**Priority:** P2 (Medium)
**Preconditions:** None

**Steps:**
1. Open resource-intensive applications (video editing, games, etc.)
2. Start recording and streaming
3. Use applications actively
4. Monitor encoding performance and stream quality
5. Check for dropped frames

**Expected Results:**
- [ ] Encoding continues under system load
- [ ] FPS may drop but doesn't stop
- [ ] Stream remains connected
- [ ] Dropped frames logged (if any)
- [ ] App remains responsive
- [ ] No crash or encoding failure

**Pass Criteria:** Encoding degrades gracefully under load, doesn't fail

---

#### **TEST-ENC-010: Simultaneous Recording and Streaming**
**Priority:** P1 (High)
**Preconditions:** Recording session configured for file output

**Steps:**
1. Start recording session (saves to file)
2. Start streaming simultaneously
3. Record and stream for 5 minutes
4. Stop both
5. Verify saved recording file
6. Compare recording quality to stream VOD

**Expected Results:**
- [ ] Both recording and streaming work simultaneously
- [ ] Saved file contains full-quality video
- [ ] Twitch stream quality acceptable
- [ ] Both outputs synchronized
- [ ] No encoding conflicts
- [ ] File saved successfully at expected location

**Pass Criteria:** Recording and streaming work concurrently without issues

**Files Referenced:**
- ArkavoKit/Sources/ArkavoRecorder/VideoEncoder.swift:60 (dual output)

---

## Error Scenario Tests

### Test Category: Comprehensive Error Handling

#### **TEST-ERR-001: Network Disconnection Mid-Stream**
**Priority:** P0 (Critical)
**Preconditions:** Stream actively publishing

**Steps:**
1. Start streaming successfully
2. Stream for 30 seconds
3. Disconnect network (Wi-Fi off or ethernet unplugged)
4. Observe app behavior for 30 seconds
5. Reconnect network
6. Attempt to restart stream

**Expected Results:**
- [ ] Stream failure detected within 10 seconds
- [ ] Error message displayed: "Network connection lost" or similar
- [ ] Statistics stop updating
- [ ] Stream status shows disconnected
- [ ] App doesn't crash
- [ ] After network restored, can start new stream
- [ ] Twitch shows stream as offline

**Pass Criteria:** Network loss detected, user informed, recovery possible

---

#### **TEST-ERR-002: Invalid Credentials After Login**
**Priority:** P2 (Medium)
**Preconditions:** User logged in

**Steps:**
1. Log in successfully
2. Revoke app access via Twitch settings: https://www.twitch.tv/settings/connections
3. Attempt to use Twitch features in app
4. Observe error handling

**Expected Results:**
- [ ] API calls fail with 401 Unauthorized
- [ ] User notified of invalid credentials
- [ ] Prompted to re-login
- [ ] Re-login flow works to restore access

**Pass Criteria:** Revoked access detected and user can re-authenticate

---

#### **TEST-ERR-003: System Permission Denied (Screen Recording)**
**Priority:** P1 (High)
**Preconditions:** Screen recording permission NOT granted

**Steps:**
1. Fresh app install or revoke screen recording permission
2. Attempt to start recording session
3. Observe error handling

**Expected Results:**
- [ ] Permission error detected
- [ ] User prompted to grant screen recording permission
- [ ] Clear instructions on how to enable (System Settings)
- [ ] After granting permission, retry succeeds

**Pass Criteria:** Permission denial handled with clear user guidance

---

#### **TEST-ERR-004: Camera Permission Denied**
**Priority:** P2 (Medium)
**Preconditions:** Camera permission NOT granted

**Steps:**
1. Revoke camera permission in System Settings
2. Enable camera in recording session
3. Attempt to start recording
4. Observe error handling

**Expected Results:**
- [ ] Camera permission error detected
- [ ] User notified and prompted to grant permission
- [ ] Recording proceeds without camera (fallback) OR blocks with clear message
- [ ] After granting permission, camera works

**Pass Criteria:** Camera permission denial handled gracefully

---

#### **TEST-ERR-005: Microphone Permission Denied**
**Priority:** P2 (Medium)
**Preconditions:** Microphone permission NOT granted

**Steps:**
1. Revoke microphone permission
2. Enable microphone audio in recording
3. Start recording and streaming
4. Observe behavior

**Expected Results:**
- [ ] Microphone permission error detected
- [ ] User notified
- [ ] Recording proceeds with system audio only OR prompts for permission
- [ ] No crash

**Pass Criteria:** Microphone permission denial handled appropriately

---

#### **TEST-ERR-006: Encoding Failure (Resource Exhaustion)**
**Priority:** P2 (Medium)
**Preconditions:** System under extreme load

**Steps:**
1. Open many resource-intensive applications
2. Start recording and streaming
3. Monitor for encoding failures
4. Check for memory/CPU errors

**Expected Results:**
- [ ] Encoding may fail under extreme load
- [ ] Error message displayed if encoding fails
- [ ] App doesn't crash
- [ ] User can stop and retry
- [ ] Graceful degradation (reduced quality) OR clear failure

**Pass Criteria:** Encoding failures handled without crash

---

#### **TEST-ERR-007: Missing Stream Key**
**Priority:** P1 (High)
**Preconditions:** None

**Steps:**
1. Navigate to Stream tab
2. Select Twitch platform
3. Leave stream key field empty
4. Click "Start Stream"

**Expected Results:**
- [ ] Validation error: "Stream key required"
- [ ] Stream does NOT start
- [ ] Error message displayed in UI
- [ ] User can enter stream key and retry

**Pass Criteria:** Empty stream key rejected with clear error

**Files Referenced:**
- ArkavoCreator/ArkavoCreator/StreamViewModel.swift:62 (validation)

---

#### **TEST-ERR-008: Corrupted Sample Buffer**
**Priority:** P3 (Low)
**Preconditions:** Recording active (difficult to trigger)

**Steps:**
1. Start recording and streaming
2. Attempt to trigger invalid sample buffer (may require code modification)
3. Observe error handling

**Expected Results:**
- [ ] Invalid sample buffer caught
- [ ] Error logged: "FLVError.invalidSampleBuffer"
- [ ] Frame skipped, encoding continues
- [ ] No app crash
- [ ] Stream continues (minor glitch acceptable)

**Pass Criteria:** Invalid buffers handled without stream failure

**Files Referenced:**
- ArkavoStreaming/Sources/ArkavoStreaming/RTMP/FLVMuxer.swift:52 (error handling)

---

## End-to-End Workflow Tests

### Test Category: Complete User Workflows

#### **TEST-E2E-001: First-Time User Complete Workflow**
**Priority:** P0 (Critical)
**Preconditions:** Fresh app install, never used before

**Steps:**
1. Launch ArkavoCreator for first time
2. Grant all system permissions (screen, camera, microphone)
3. Navigate to Dashboard
4. Click "Login with Twitch"
5. Complete OAuth login
6. Retrieve stream key from Twitch dashboard
7. Navigate to Stream tab
8. Select Twitch platform
9. Enter stream key
10. Start recording session
11. Start streaming
12. Stream for 2 minutes
13. Stop streaming
14. Stop recording
15. Logout from Twitch

**Expected Results:**
- [ ] All steps complete without errors
- [ ] User successfully goes live on Twitch
- [ ] Stream quality acceptable
- [ ] Recording saved locally
- [ ] Logout successful
- [ ] Overall experience smooth

**Pass Criteria:** Complete workflow from install to streaming succeeds

**Estimated Time:** 10-15 minutes

---

#### **TEST-E2E-002: Returning User Workflow**
**Priority:** P0 (Critical)
**Preconditions:** User previously logged in, stream key saved

**Steps:**
1. Launch ArkavoCreator
2. Verify already logged into Twitch (no re-login)
3. Navigate to Stream tab
4. Verify stream key auto-filled from Keychain
5. Start recording
6. Start streaming immediately
7. Stream for 2 minutes
8. Stop streaming
9. Restart streaming (without app restart)
10. Stream for 1 minute
11. Stop streaming and recording

**Expected Results:**
- [ ] No re-login required
- [ ] Stream key persisted from previous session
- [ ] Quick workflow to go live (< 1 minute)
- [ ] Can restart stream without issues
- [ ] All features work as expected

**Pass Criteria:** Returning user can quickly resume streaming

**Estimated Time:** 5 minutes

---

#### **TEST-E2E-003: Platform Switching (Twitch → YouTube → Custom)**
**Priority:** P1 (High)
**Preconditions:** User has credentials for multiple platforms

**Steps:**
1. Start stream on Twitch
2. Stream for 1 minute
3. Stop Twitch stream
4. Switch to YouTube platform
5. Enter YouTube stream key
6. Start YouTube stream
7. Stream for 1 minute
8. Stop YouTube stream
9. Switch to Custom RTMP
10. Enter custom RTMP URL and key
11. Start custom stream (or verify validation)

**Expected Results:**
- [ ] Platform switching works smoothly
- [ ] Each platform's stream key saved independently
- [ ] No conflicts between platform configs
- [ ] All platforms function correctly
- [ ] UI updates appropriately for each platform

**Pass Criteria:** User can switch platforms without issues

**Estimated Time:** 10 minutes

**Files Referenced:**
- ArkavoCreator/ArkavoCreator/StreamViewModel.swift:37 (platform selection)

---

#### **TEST-E2E-004: Recording + Streaming with Multiple Inputs**
**Priority:** P1 (High)
**Preconditions:** Camera and microphone available

**Steps:**
1. Start recording session with:
   - Screen capture enabled
   - Camera enabled (picture-in-picture)
   - Microphone enabled
   - System audio enabled
2. Start Twitch stream
3. Perform activities:
   - Play video with audio
   - Speak into microphone
   - Move in front of camera
   - Navigate through UI
4. Stream for 5 minutes
5. Stop stream and recording
6. Review both saved file and Twitch VOD

**Expected Results:**
- [ ] All inputs captured simultaneously
- [ ] Screen content visible
- [ ] Camera feed overlaid correctly
- [ ] Both audio sources mixed properly
- [ ] Saved file contains all sources
- [ ] Twitch stream includes all sources
- [ ] Everything synchronized

**Pass Criteria:** Multi-input recording and streaming works flawlessly

**Estimated Time:** 10 minutes

---

#### **TEST-E2E-005: Error Recovery and Retry**
**Priority:** P1 (High)
**Preconditions:** None

**Steps:**
1. Attempt to stream with invalid stream key (expect failure)
2. Observe error message
3. Correct stream key
4. Retry streaming (should succeed)
5. Disconnect network mid-stream
6. Observe error handling
7. Reconnect network
8. Restart stream (should succeed)
9. Complete stream normally

**Expected Results:**
- [ ] Each error detected and reported clearly
- [ ] User can correct and retry after each failure
- [ ] No persistent errors after correction
- [ ] Final stream succeeds
- [ ] No app crashes throughout

**Pass Criteria:** User can recover from errors and complete workflow

**Estimated Time:** 10 minutes

---

## Test Execution Tracking

### Test Execution Summary

**Test Session Information:**
- **Tester Name:** ___________________
- **Test Date:** ___________________
- **App Version:** ___________________
- **Platform:** [ ] iOS 26  [ ] iPadOS 26  [ ] macOS 26
- **Device:** ___________________
- **Twitch Test Account:** ___________________

### Test Results Overview

| Category | Total Tests | Passed | Failed | Blocked | Not Run |
|----------|-------------|--------|--------|---------|---------|
| OAuth Authentication | 12 | | | | |
| RTMP Streaming | 15 | | | | |
| Video/Audio Encoding | 10 | | | | |
| Error Scenarios | 8 | | | | |
| End-to-End Workflows | 5 | | | | |
| **TOTAL** | **50** | | | | |

### Detailed Test Results

| Test ID | Test Name | Status | Notes | Bugs Filed |
|---------|-----------|--------|-------|------------|
| TEST-AUTH-001 | First-Time Twitch Login | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-002 | Token Exchange Verification | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-003 | User Info Retrieval | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-004 | Token Persistence | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-005 | Logout Functionality | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-006 | OAuth Callback Error Handling | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-007 | Invalid Callback URL | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-008 | Network Failure During Token Exchange | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-009 | Expired Token Handling | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-010 | Invalid Client ID/Configuration | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-011 | WebView Dismissal During Login | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-AUTH-012 | Concurrent Login Attempts | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-001 | RTMP Server Connection | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-002 | RTMP Handshake Verification | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-003 | RTMP Publish Command | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-004 | Stream Statistics Monitoring | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-005 | Stream Stop and Cleanup | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-006 | Invalid Stream Key | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-007 | Network Interruption During Streaming | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-008 | Connection Timeout | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-009 | Server Unreachable | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-010 | Streaming Without Active Recording | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-011 | Concurrent Stream Attempts | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-012 | Handshake Failure | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-013 | Large Buffer/Memory Test | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-014 | Rapid Start/Stop Cycles | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-RTMP-015 | Stream Key with Special Characters | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-001 | H.264 Video Encoding | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-002 | AAC Audio Encoding | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-003 | FLV Container Format | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-004 | Multi-Source Audio | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-005 | Frame Rate Validation | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-006 | Bitrate Validation | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-007 | Screen Content Encoding | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-008 | Camera Feed Encoding | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-009 | Encoding Performance Under Load | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ENC-010 | Simultaneous Recording and Streaming | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ERR-001 | Network Disconnection Mid-Stream | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ERR-002 | Invalid Credentials After Login | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ERR-003 | System Permission Denied (Screen) | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ERR-004 | Camera Permission Denied | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ERR-005 | Microphone Permission Denied | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ERR-006 | Encoding Failure (Resource Exhaustion) | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ERR-007 | Missing Stream Key | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-ERR-008 | Corrupted Sample Buffer | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-E2E-001 | First-Time User Complete Workflow | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-E2E-002 | Returning User Workflow | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-E2E-003 | Platform Switching | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-E2E-004 | Recording + Streaming Multi-Input | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |
| TEST-E2E-005 | Error Recovery and Retry | [ ] Pass<br>[ ] Fail<br>[ ] Blocked<br>[ ] Skip | | |

### Testing Notes

**Environment Issues:**
```
(Record any setup problems, environment configuration issues, etc.)
```

**General Observations:**
```
(Overall impressions, performance notes, user experience feedback)
```

**Recommendations:**
```
(Suggestions for improvements, additional tests needed, etc.)
```

---

## Bug Reporting Template

When filing bugs discovered during testing, use this template:

```markdown
### Bug Report: [Short Description]

**Test ID:** TEST-XXX-XXX
**Severity:** [ ] Critical  [ ] High  [ ] Medium  [ ] Low
**Priority:** [ ] P0  [ ] P1  [ ] P2  [ ] P3

**Environment:**
- Platform: [iOS/iPadOS/macOS] 26
- Device: [Device model]
- App Version: [Version number]
- Twitch Account: [Test account used]

**Steps to Reproduce:**
1.
2.
3.

**Expected Result:**
[What should happen]

**Actual Result:**
[What actually happened]

**Screenshots/Logs:**
[Attach relevant screenshots, console logs, or error messages]

**Reproducibility:**
[ ] Always  [ ] Sometimes  [ ] Once

**Workaround:**
[If any workaround exists]

**Additional Context:**
[Any other relevant information]

**Related Files:**
[Reference specific source files if identified]
```

---

## Appendix: Known Limitations & Gaps

Based on code analysis, these are known limitations to be aware of during testing:

### Security Issues:
1. **Access tokens stored in UserDefaults** (should use Keychain)
2. **No RTMPS support** (plain RTMP only, unencrypted)
3. **Secrets.swift contains actual credentials** (should not be committed)

### Authentication:
1. **No automatic stream key retrieval** (Twitch API limitation)
2. **No token refresh mechanism** (tokens expire without renewal)
3. **No session expiration detection**

### Streaming:
1. **No connection retry logic** (network failures are fatal)
2. **No bandwidth adaptation** (fixed bitrate)
3. **Incomplete RTMP implementation** (simplified commands)
4. **No server response validation** (commands sent without waiting for ACK)
5. **No stream health monitoring**

### Error Handling:
1. **Minimal logging** (print statements only)
2. **Generic error messages** (limited user feedback)
3. **Silent FLV packet failures**

### Testing:
1. **Zero existing test coverage**
2. **No CI/CD validation**

These gaps should be considered when evaluating test results. Some test failures may be due to these known limitations rather than new bugs.

---

## Test Completion Sign-Off

**Tester Signature:** _____________________
**Date Completed:** _____________________
**Overall Status:** [ ] All Tests Passed  [ ] Tests Passed with Known Issues  [ ] Critical Failures Found

**Summary:**
```
[Brief summary of test execution results and overall assessment]
```
