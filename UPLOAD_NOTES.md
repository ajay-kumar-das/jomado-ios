# Upload notes

This snapshot is based on GitHub `main` commit `b6cb33afdb153abc17bffd03973768f30cc060ad` and includes the production-hardening changes prepared after that commit.

## Included on top of `b6cb33a`

1. **AlarmKit packaging fix**
   - `project.yml` uses `Config/Info.plist` as `INFOPLIST_FILE` and disables generated plist creation.
   - The built app must retain `NSAlarmKitUsageDescription`.
   - CI verifies the built app's AlarmKit usage description, version, bundle ID, hydration content, and privacy manifest.
   - `AlarmScheduler` fails with an actionable local configuration error if the installed bundle ever loses the AlarmKit usage description.

2. **Hydration Setup polish**
   - Every day / Weekdays / Weekend shortcuts.
   - Preview of every generated AlarmKit wall-clock time before saving.
   - Explicit recurrence summary.

3. **Core invariant preserved**
   - Alarm `Silence` records acknowledgement only.
   - Hydration is completed only through the explicit `I drank water` action.

## Upload/build

Replace the repository contents with this directory, commit, and push to `main` (or preferably a branch first). GitHub Actions will run the core tests, validate resources, generate the Xcode project, compile the unsigned iPhone build, validate the **built** Info.plist/resources, and publish the IPA artifact.

For a local Xcode build:

```bash
brew install xcodegen
xcodegen generate
open Jomado.xcodeproj
```

Select your Apple Developer team and run on an iPhone with iOS 26+ for AlarmKit validation.
