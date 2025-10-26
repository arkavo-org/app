# Manual Test Guide: Avatar Rendering

## Acceptance Criteria
✅ Load a VRM model and see it rendered in the preview

## Test Procedure

### ⭐ Recommended: Use Local VRM File (Fastest & Most Reliable)

1. **Launch ArkavoCreator**
   ```bash
   open ArkavoCreator/build/Debug/ArkavoCreator.app
   ```

2. **Navigate to Record Mode**
   - Click "Record" in the sidebar
   - Verify Recording Mode picker shows "Avatar" and "Camera"

3. **Manually Copy Test Model**
   ```bash
   # Create VRM models directory
   mkdir -p ~/Library/Containers/com.arkavo.ArkavoCreator/Data/Documents/VRMModels

   # Copy AliciaSolid.vrm
   cp /Users/paul/Projects/GameOfMods/Resources/vrm/AliciaSolid.vrm \
      ~/Library/Containers/com.arkavo.ArkavoCreator/Data/Documents/VRMModels/
   ```

4. **Restart App** (to refresh model list)

5. **Select and Load Model**
   - Click "AliciaSolid.vrm" in the model list
   - Click "Load Avatar" button
   - Wait for loading...

6. **✅ Verify Rendering**
   - Avatar should appear in the green preview area
   - No error alerts should appear
   - You should see the 3D model rendered

### Option 2: Download from Direct URL

1. **Navigate to Record Mode** (as above)

2. **Download Model**
   - Paste a direct .vrm file URL into "VRM URL" field
   - Click "Download" button
   - Wait for download to complete

3. **Load Model**
   - Model should appear in "Select Avatar" list
   - Click on it to select
   - Click "Load Avatar"

4. **✅ Verify Rendering** (as above)

### Option 3: VRM Hub URL (May Require Auth)

1. **Navigate to Record Mode**

2. **Try VRM Hub URL**
   - Paste: `https://hub.vroid.com/en/characters/515144657245174640/models/6438391937465666012`
   - Click "Download"
   - May show "authentication required" error (expected for some models)

3. **If Auth Required**
   - Download model manually from VRM Hub
   - Use Option 1 or 2 with direct .vrm URL

## Expected Results

### ✅ Success Criteria
- Model appears in preview with green background
- 3D avatar is visible and properly rendered
- No crash or error alerts
- Model rotates/animates (if animations present)

### Lip Sync Test (Optional)
1. Enable "Enable Lip Sync" toggle
2. Grant microphone permission
3. Speak into microphone
4. Mouth should move with audio amplitude

## Troubleshooting

### Model Not in List
- Restart app after manually copying file
- Check file is in correct directory (see step 3 above)
- Verify .vrm extension

### Load Error
- Check console logs for error details
- Ensure Metal is available (macOS 26.0+)
- Verify .vrm file is valid VRM 1.0 format

### No Rendering
- Check green preview area exists
- Look for error messages in console
- Verify model loaded successfully (check logs)

## Console Logs to Watch For

```
[VRMAvatarRenderer] Loading model from: <path>
[VRMAvatarRenderer] Model loaded successfully, nodes: <count>
[VRMAvatarRenderer] Model loaded into renderer
```

If you see these logs, the model loaded correctly!
