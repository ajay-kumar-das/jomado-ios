# Jomado iOS

Native SwiftUI iOS 26+ MVP for the local-first Jomado accountability companion.

## Included
- Hydration schedules with AlarmKit
- Stop/silence != complete semantics
- Structured reminder state machine
- 128 curated local reminder experiences across 8 strategies and 4 urgency stages
- Momo, Sparky and Pip placeholder mascots with animated SwiftUI rendering
- Normal → yellow → orange → red escalation
- Local SwiftData persistence
- Adaptive local content ranking with cooldown, novelty, strategy/mascot effectiveness and 12% exploration
- Completion scoring and on-device insights
- Explicit content feedback/preferences
- Developer simulator for every urgency level and strategy
- No cloud account and no generative AI in V1

## Requirements
- macOS with Xcode 26+
- iOS 26+ physical device for AlarmKit validation
- XcodeGen (`brew install xcodegen`) OR create an Xcode app target and add the included sources/resources manually

## Open the project
1. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` from `com.example.Jomado` to your bundle ID.
2. Change the app-group value in both `Config/Jomado.entitlements` and `SharedAlarmEventQueue.swift` from `group.com.example.jomado` to an App Group enabled for your Apple Developer identifier.
3. In this directory run `xcodegen generate`.
4. Open `Jomado.xcodeproj`.
5. Select your Apple Developer team.
6. Confirm the App Group capability matches the value above.
7. Run on an iPhone with iOS 26+ and grant Alarm access.

## Core tests
`cd JomadoCore && swift test`

The core package is intentionally platform-light so state-machine and recommendation behavior can be tested independently of SwiftUI/AlarmKit.

## Important iOS behavior
AlarmKit supplies a system stop control. Jomado records stopping/silencing as acknowledgement only. The commitment remains pending until the user completes or explicitly skips it. AlarmKit authorization requires `NSAlarmKitUsageDescription`, already present in `Config/Info.plist`.

## AI verification
Not included by design. Add it later behind a `VerificationProvider` interface after the core reminder loop is validated.
