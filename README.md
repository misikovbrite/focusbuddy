# FocusBuddy

A macOS menu bar app with an animated robot that helps you stay focused using camera-based attention tracking and gesture controls.

## Features

### Robot in the Notch
- Animated robot face lives in the macOS notch area (Dynamic Island style)
- Expands on hover to show stats and controls
- Reacts to your focus state with different emotions and animations

### Camera-Based Focus Tracking
- Uses Vision framework for face detection
- Tracks if you're looking at the screen
- Only actively monitors during Pomodoro work sessions
- Distraction site monitoring works always (Instagram, YouTube, Twitter, etc.)

### Gesture Controls
| Gesture | Action |
|---------|--------|
| 👋 **Wave** | Toggle Pomodoro timer (start/stop) |
| 👍 **Thumbs up** | Toggle break mode (working ↔ break) |

### Pomodoro Timer
- Configurable work/break durations
- Visual timer display in expanded panel
- Sound notifications for session changes
- Three states: `idle`, `working`, `onBreak`

### Robot States & Emotions
The robot displays different moods based on your focus:

| State | Eyes | Trigger |
|-------|------|---------|
| Happy | Green | Focused, looking at screen |
| Concerned | Yellow | Starting to look away |
| Worried | Orange | Distracted for a while |
| Angry | Red | On distracting site |
| Sad | Blue | Prolonged distraction |
| Love | Pink + hearts | Double-click easter egg |
| Celebrating | Rainbow | High focus percentage |

## Architecture

```
FocusBuddy/
├── FocusBuddyApp.swift      # Main app, window management, UI
├── CameraManager.swift       # Camera access, face & gesture detection
├── FocusViewModel.swift      # Focus state logic, monitoring
├── FocusState.swift          # Attention state, mood calculations
├── AppSettings.swift         # User settings, Pomodoro logic
├── SoundManager.swift        # Audio feedback (synthesized tones)
├── RobotView.swift           # Legacy robot view
├── RobotState.swift          # Robot state enum
├── ContentView.swift         # Legacy content view
└── Info.plist                # Permissions
```

## Key Components

### CameraManager.swift
Handles all camera and Vision framework interactions:

- **Face Detection**: `VNDetectFaceLandmarksRequest`
  - Tracks face presence
  - Analyzes head angle (yaw, pitch, roll)
  - Determines if user is looking at screen

- **Gesture Detection**: `VNDetectHumanHandPoseRequest`
  - Wave detection: Tracks wrist X position, counts direction changes
  - Thumbs up: Checks if thumb is highest point, extended upward

```swift
// Published properties
@Published var isFaceDetected: Bool
@Published var headAngle: Double
@Published var isWaving: Bool
@Published var isShowingStop: Bool  // Thumbs up detected
```

### FocusViewModel.swift
Manages focus monitoring logic:

- Updates state every 0.5 seconds
- Camera tracking only active during `pomodoroState == .working`
- Distraction site detection always active
- Handles mood transitions and sound triggers

```swift
// Key logic in updateState()
if isPomodoroActive {
    // Track face, update attention
} else {
    // Passive mode, robot stays neutral
}

// Distracting sites always trigger reaction
if currentContext.isDistracting {
    attentionState.forceDistracted()
}
```

### AppSettings.swift
User preferences and Pomodoro management:

```swift
// Pomodoro states
enum PomodoroState {
    case idle      // Not running
    case working   // Active focus session
    case onBreak   // Relaxed mode, no strict monitoring
}

// Key settings
var pomodoroWorkMinutes: Int = 25
var pomodoroBreakMinutes: Int = 5
var whitelistedSites: [String] = []
```

### SoundManager.swift
Synthesized audio feedback using AVAudioEngine:

| Sound | Description | When |
|-------|-------------|------|
| `playWarningSound()` | Gentle double tap | Starting to distract |
| `playDistractedSound()` | Descending minor third | Fully distracted |
| `playWelcomeBackSound()` | Ascending major chord | Returned to focus |
| `playPomodoroStart()` | Ascending fifth | Work session starts |
| `playPomodoroEnd()` | Descending triad | Work session ends |
| `playBreakStart()` | Soft fourth interval | Break begins |
| `playClick()` | Soft tap | Button/gesture feedback |

## UI Components

### ExtendedNotchView
Main robot interface in the notch:

- **Collapsed**: Small robot face in top-right corner
- **Expanded on hover**:
  - Focus time stat (left)
  - Large robot face (center)
  - Distraction count (right)
  - Control buttons (pause, pomodoro, settings)
  - Pomodoro timer display

### RobotFace
Animated robot face with:
- Blinking eyes (random interval)
- Pupil tracking (follows mouse)
- Squint on hover
- Head tilt animations
- Glowing antenna
- Color changes based on mood

### NotchWithEars Shape
Custom shape mimicking MacBook notch with sharp "ears"

## Gesture Detection Details

### Wave Detection
```swift
// Algorithm:
// 1. Track wrist X position over 1 second
// 2. Filter small movements (< 6% of frame width)
// 3. Count direction changes (left↔right)
// 4. 3+ direction changes = wave detected
// 5. 5 second debounce between detections

private let waveDebounce: TimeInterval = 5.0
let minMovement = 0.06  // 6% of frame
let requiredDirectionChanges = 3
```

### Thumbs Up Detection
```swift
// Algorithm:
// 1. Get thumb tip and all fingertips
// 2. Check thumb is highest point (above all fingers by 5%+)
// 3. Check thumb is extended (tip above knuckle)
// 4. Check thumb is much higher than average finger height (8%+)
// 5. 3 second debounce

private let stopDebounce: TimeInterval = 3.0
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+F` | Toggle pause |
| `Cmd+Shift+P` | Toggle Pomodoro |

## Permissions Required

```xml
<!-- Info.plist -->
<key>NSCameraUsageDescription</key>
<string>FocusBuddy uses the camera to see if you're working.</string>

<key>NSAppleEventsUsageDescription</key>
<string>FocusBuddy wants to check which site is open in your browser.</string>
```

## Distracting Sites Detection

The app monitors active browser tabs for distracting sites:
- Instagram
- YouTube
- Twitter/X
- Facebook
- TikTok
- Reddit
- Netflix
- (Configurable whitelist in settings)

## Future Ideas

- [ ] Statistics dashboard (daily/weekly focus reports)
- [ ] More gesture controls (peace sign, thumbs down)
- [ ] Custom robot skins/themes
- [ ] Focus goals and achievements
- [ ] Integration with calendar (auto-start during meetings)
- [ ] Break reminders with stretching exercises
- [ ] Multi-monitor support
- [ ] iOS companion app
