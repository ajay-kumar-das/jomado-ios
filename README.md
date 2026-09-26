# Jomado iOS

Version 0.3 companion-delivery iteration.

Native SwiftUI iOS 26+ hydration MVP for the local-first Jomado accountability companion.

## Included
- Hydration routines with start/end time, interval, and weekday selection
- One stable, recurring AlarmKit alarm per generated time slot
- Alarm reconciliation after edits, permission changes, app relaunch, and daemon drift
- Relative wall-clock schedules that follow timezone and daylight-saving changes
- Duplicate intent ingestion protection and stale reminder handling
- Stop/silence != complete semantics
- Structured reminder state machine
- 128 curated local reminder experiences across 8 strategies and 4 urgency stages
- Momo, Sparky and Pip placeholder mascots with animated SwiftUI rendering
- Normal → yellow → orange → red escalation
- Local SwiftData persistence
- Adaptive local content ranking with cooldown, novelty, strategy/mascot effectiveness and 12% exploration
- Completion scoring and on-device insights
- Explicit content feedback/preferences
- Validated bundled content with safe on-device fallback messages
- Privacy manifest declaring local-only UserDefaults use and no collected data
- Developer simulator for every urgency level and strategy
- No cloud account and no generative AI in V1

## Requirements
- macOS with Xcode 26+
- iOS 26+ physical device for AlarmKit validation
- XcodeGen (`brew install xcodegen`) OR create an Xcode app target and add the included sources/resources manually

## Open the project
1. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` if `com.ajaydas.jomado` is not your registered bundle ID.
2. In this directory run `xcodegen generate`.
3. Open `Jomado.xcodeproj`.
4. Select your Apple Developer team.
5. Run on an iPhone with iOS 26+ and grant Alarm access.

## Core tests
`cd JomadoCore && swift test`

The core package is intentionally platform-light so state-machine and recommendation behavior can be tested independently of SwiftUI/AlarmKit.

## Important iOS behavior
AlarmKit supplies a system stop control. Jomado records stopping/silencing as acknowledgement only. The commitment remains pending until the user completes or explicitly skips it. AlarmKit authorization requires `NSAlarmKitUsageDescription`, already present in `Config/Info.plist`.

Jomado diffs its persisted alarm IDs against `AlarmManager` and changes only missing, stale, or reconfigured alarms. It does not cancel and recreate healthy alarms on every launch.

## Companion delivery (0.3)
- New routines default to Companion mode: local notifications plus a Lock Screen / Dynamic Island Live Activity.
- Existing routines retain Alarm mode during migration so an update does not silently weaken already-configured reminders.
- Dismissing a notification or silencing an alarm never completes a task.
- iOS-delivered local notifications continue to fire while Jomado is closed.
- The Live Activity updates locally once started and the client captures an ActivityKit push-to-start token. A backend/APNs registration path is still required before Jomado can start a brand-new Live Activity at reminder time when the app process is completely terminated.
- AlarmKit remains available as an explicit delivery mode.
