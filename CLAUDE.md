# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TomatoBar is a macOS Pomodoro timer application that lives in the menu bar. It's built with SwiftUI and uses a state machine to manage timer states. The app is fully sandboxed and follows Apple's security guidelines.

## Architecture

The application follows a clean architecture with the following main components:

- **App.swift**: Main application entry point and menu bar status item management
- **State.swift**: State machine definitions (idle, work, rest) and events (startStop, timerFired, skipRest)
- **Timer.swift**: Core timer logic using SwiftState for state management, @AppStorage for persistence
- **View.swift**: SwiftUI views for the popover UI (intervals, settings, sounds)
- **Notifications.swift**: Local notification management
- **Player.swift**: Audio playback for timer sounds (windup, ding, ticking)
- **Log.swift**: Event logging system for productivity tracking

## Key Dependencies

- **SwiftState**: State machine implementation for managing timer states
- **KeyboardShortcuts**: Global hotkey support (⌘⌥P by default)
- **LaunchAtLogin**: Login item management

## Project Structure

The app consists of 9 main Swift files in the `TomatoBar/` directory:
- `App.swift`: Main app entry point with `TBApp` struct and `TBStatusItem` class for menu bar management
- `State.swift`: State machine definitions (`TBStateMachineStates`, `TBStateMachineEvents`)
- `Timer.swift`: Core timer logic (`TBTimer` class) with state machine integration
- `View.swift`: SwiftUI views (`TBPopoverView`, `TBIntervalsView`, `TBSettingsView`, `TBSoundsView`)
- `Notifications.swift`: Local notification management (`TBNotificationCenter`)
- `Player.swift`: Audio playback (`TBPlayer`) for timer sounds
- `Log.swift`: Event logging system (`TBLogEvent*` classes)
- `WorkCompletionView.swift`: Work completion popup UI (`WorkCompletionView`, `WorkCompletionWindow`)
- `WorkCompletionService.swift`: Data upload service (`WorkCompletionService`) for API integration

Localization files are in `en.lproj/` and `zh-Hans.lproj/` directories.

## Work Completion Feature

When a pomodoro timer completes, the app now shows a popup window where users can:
1. Enter a description of what they accomplished
2. Add tags (comma-separated)
3. Submit, skip, or cancel the recording

The data is uploaded to a configurable API endpoint (set in Settings) or saved locally if:
- No API endpoint is configured
- Upload fails

### API Configuration

Users can configure their API endpoint in Settings → API Endpoint. The endpoint should accept POST requests with JSON data:
```json
{
  "description": "User's work description",
  "tags": ["tag1", "tag2"],
  "timestamp": "2023-12-01T10:30:00Z",
  "app_version": "3.0"
}
```

## Development Commands

### Building and Running

Since this is a macOS app using Xcode, you'll need to use Xcode to build and run:

1. Open `TomatoBar.xcodeproj` in Xcode
2. Build and run using Xcode's Build & Run command (⌘R)

### Linting

The project uses SwiftLint for code style enforcement with Swift 5.0. The configuration file `.swiftlint.yml` disables trailing commas and opening brace rules.

To lint the code:
```bash
swiftlint
```

### Icon Generation

To generate app icons and menu bar icons:

```bash
cd Icons
./convert.sh appicon    # Generate app icons
./convert.sh baricon    # Generate menu bar icons
```

This requires ImageMagick (`convert` command) to be installed.

## State Machine

The timer uses a state machine with three states:
- **idle**: Timer not running
- **work**: Active work interval
- **rest**: Break interval (short or long based on work intervals completed)

State transitions are triggered by:
- `startStop`: Toggle between idle/work or work/idle, rest/idle
- `timerFired`: Work → rest, rest → idle/work (based on stopAfterBreak setting)
- `skipRest**: Rest → work (from notification action)

## Configuration

All user preferences are stored using `@AppStorage`:
- `workIntervalLength`: Work duration in minutes (default: 25)
- `shortRestIntervalLength`: Short break duration (default: 5)
- `longRestIntervalLength`: Long break duration (default: 15)
- `workIntervalsInSet`: Number of work intervals before long break (default: 4)
- `stopAfterBreak`: Whether to stop timer after break (default: false)
- `showTimerInMenuBar`: Display timer countdown in menu bar (default: true)

## Localization

The app supports English and Chinese localization:
- `en.lproj/Localizable.strings`: English strings
- `zh-Hans.lproj/Localizable.strings`: Chinese strings

## URL Scheme

The app responds to `tomatobar://` URLs:
- `tomatobar://startStop`: Start/stop the timer

## Logging

State transitions are logged to:
`~/Library/Containers/com.github.ivoronin.TomatoBar/Data/Library/Caches/TomatoBar.log`

This JSON log can be used for productivity analysis.

## Key Implementation Details

- Timer accuracy is maintained using DispatchSourceTimer with strict scheduling
- State transitions are thread-safe and run on the main queue
- Audio playback uses AVAudioPlayer with proper session management
- Notifications use UNUserNotificationCenter with actionable buttons
- Menu bar updates are performed on the main thread
- The app uses a transient popover that closes when clicked outside

## Security

The app is fully sandboxed with minimal entitlements:
- Only requires App Sandbox capability
- No network access or file system permissions needed
- URL scheme handling is properly declared in Info.plist