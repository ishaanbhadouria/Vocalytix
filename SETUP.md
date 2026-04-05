# Avaixa - Phase 1 Setup Guide

## Prerequisites
1. Install Flutter:
```bash
cd ~/
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:$HOME/flutter/bin"
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc
flutter doctor
```

## Installation Steps

### 1. Navigate to project
```bash
cd /Users/ishaanbhadouria/Desktop/CES/avaixa
```

### 2. Get dependencies
```bash
flutter pub get
```

### 3. Enable web support (if not already enabled)
```bash
flutter config --enable-web
```

### 4. Run the app
```bash
flutter run -d chrome
```

## How It Works

### Architecture
```
Flutter (Dart)
    ↕ JS Interop
JavaScript (MediaPipe)
    ↕
WebRTC Camera API
```

### File Structure
- `lib/main.dart` - App entry point
- `lib/screens/practice_screen.dart` - Main UI with camera preview
- `web/media_pipe.js` - MediaPipe face detection logic
- `web/index.html` - HTML with MediaPipe CDN
- `web/manifest.json` - PWA configuration

### JS ↔ Dart Communication

**Dart → JS:**
```dart
js.context.callMethod('initializeMediaPipe');  // Start camera
js.context.callMethod('stopCamera');            // Stop camera
```

**JS → Dart:**
```javascript
window.onFaceDetection({
  facePresent: true,
  headTilt: 'Neutral',
  gazeDirection: 'Center'
});
```

### What Gets Detected
1. **Face Present** - Boolean detection
2. **Head Tilt** - Neutral / Tilted Left / Tilted Right
3. **Gaze Direction** - Center / Left / Right

### Camera Access
- Requests 1280x720 user-facing camera
- Displays live preview with overlay canvas
- MediaPipe runs at ~30 FPS on video stream

## Troubleshooting

### Camera not working
- Grant camera permissions in browser
- Check browser console for errors
- Ensure HTTPS or localhost (required for camera API)

### MediaPipe not loading
- Check internet connection (CDN required)
- Falls back to basic browser FaceDetector API
- Check console: "MediaPipe Face Detection initialized"

### Build errors
```bash
flutter clean
flutter pub get
flutter run -d chrome --web-renderer html
```

## Next Steps (Future Phases)
- [ ] Voice analysis
- [ ] Posture tracking (MediaPipe Pose)
- [ ] Gesture detection
- [ ] Performance scoring
- [ ] Session recording
