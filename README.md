# AXIS - AirPods Posture Tracker

A macOS menu bar application that uses AirPods Pro motion sensors to monitor and improve your posture in real-time.

## Features

### 🎯 Real-Time Posture Monitoring
- Tracks head position using AirPods Pro/Max built-in motion sensors
- Monitors pitch (forward/backward tilt) and roll (side-to-side tilt)
- Provides instant feedback when bad posture is detected

### 🔧 Smart Calibration System
- Interactive calibration flow with visual feedback
- Tracks your natural range of motion during calibration
- Automatically calculates personalized posture thresholds (40% of your movement range)
- Circular motion tracking with animated orbit particles
- Progress indicator showing calibration completion

### ⚠️ Fullscreen Alerts
- Beautiful glass-morphism alert overlay when bad posture persists
- Customizable alert delay (5-30 seconds)
- Smooth fade-in/fade-out animations
- Non-intrusive design that encourages posture correction

### 📊 Data Logging & Analytics
- Automatic logging of posture data every second
- Uploads to AWS S3 every 30 seconds
- Tracks pitch, roll, timestamp, and posture status (good/bad)
- Persistent storage for long-term posture analysis

### 🎨 Modern UI Design
- Clean menu bar integration with custom logo
- Apple glass-morphism aesthetic
- Smooth animations and transitions
- Minimalist popover interface

## Requirements

- macOS 12.0 or later
- AirPods Pro or AirPods Max
- Xcode 14.0+ (for building)
- AWS account (for data logging)

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd AirpodPosture
```

2. Set up AWS credentials in `.env` file:
```bash
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_SESSION_TOKEN=your_session_token
S3_BUCKET_NAME=your_bucket_name
AWS_DEFAULT_REGION=us-east-1
```

3. Open `AirpodPosture.xcodeproj` in Xcode

4. Build and run the application

## Usage

### First Time Setup

1. **Launch the app** - AXIS icon appears in your menu bar
2. **Click the calibration button** (scope icon) in the popover
3. **Move your head in a circular motion** until the progress reaches 100%
4. **Sit in your ideal posture** and click "Set Neutral Posture"

### Daily Use

1. **Click the AirPods icon** in the popover to start tracking (turns blue when active)
2. **Adjust alert delay** using the clock icon (cycles through 5-30 seconds)
3. **Work normally** - the app monitors your posture in the background
4. **Correct posture** when the fullscreen alert appears

### Recalibration

- Click the calibration button anytime to recalibrate
- Recommended after changing your desk setup or seating position

## How It Works

### Motion Tracking
- Uses CoreMotion's `CMHeadphoneMotionManager` to access AirPods sensors
- Samples motion data continuously at high frequency
- Calculates relative attitude from calibrated neutral position

### Posture Detection
- Compares current head position to calibrated neutral posture
- Uses dynamic thresholds based on your calibration range
- Triggers alerts only after sustained bad posture (configurable delay)

### Data Pipeline
1. Motion data captured every frame
2. Posture status logged every second
3. Data batched and uploaded to S3 every 30 seconds
4. JSON format: `{userId, sessions: [{timestamp, pitch, roll, status}]}`

## Architecture

```
AirpodPostureApp.swift    - App delegate, motion management, posture checking
ContentView.swift         - UI components, calibration view, alerts
PostureLogger.swift       - AWS S3 integration, data persistence
```

### Key Components

- **MotionManager**: Observable object managing tracking state and calibration
- **AppDelegate**: Handles motion updates, posture checking, and alerts
- **CalibrationView**: Interactive calibration interface with progress tracking
- **BadPostureView**: Fullscreen alert with glass-morphism design
- **PostureLogger**: S3 upload manager with automatic batching

## Customization

### Threshold Sensitivity
Edit in `AirpodPostureApp.swift`:
```swift
let forwardTiltThreshold = pitchRange > 10 ? -(pitchRange * 0.4) : -20.0
let sideTiltThreshold = rollRange > 10 ? (rollRange * 0.4) : 20.0
```

### Alert Timing
Modify in `ContentView.swift`:
```swift
// Cycle through: 5 -> 10 -> 15 -> 20 -> 25 -> 30 -> 5
motionManager.badPostureDuration = TimeInterval(currentValue + 5)
```

### Upload Frequency
Change in `PostureLogger.swift`:
```swift
private let uploadInterval: TimeInterval = 30 // seconds
```

## Privacy & Data

- All motion data stays on your device until uploaded to your personal S3 bucket
- No third-party analytics or tracking
- You control your AWS credentials and data storage
- Data format is simple JSON for easy analysis

## Troubleshooting

**AirPods not detected:**
- Ensure AirPods Pro/Max are connected and worn
- Check Bluetooth connection
- Restart the app

**Calibration not working:**
- Make sure you're wearing the AirPods
- Move your head in a full circular motion
- Try recalibrating if thresholds seem off

**S3 upload failing:**
- Verify AWS credentials in `.env` file
- Check S3 bucket permissions
- Ensure internet connection is active

## Future Enhancements

- [ ] Historical posture analytics dashboard
- [ ] Customizable alert sounds
- [ ] Multiple user profiles
- [ ] Export data to CSV
- [ ] Posture score and trends
- [ ] Reminder notifications

## License

MIT License - feel free to modify and distribute

## Credits

Built with SwiftUI, CoreMotion, and AWS SDK for Swift
