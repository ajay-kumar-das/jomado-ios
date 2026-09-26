# Jomado Iteration 22 — Xcode 26.6 concurrency build fix

Base reconstructed from GitHub branch `feature/notification` at commit:
`28e9ca47fa17df90e6464b5b995f7bfac155977d`

Then applied the run #12 Swift 6 concurrency fixes:

- `CompanionActivityCoordinator.swift`
  - scopes the Xcode 26.4+ ActivityKit `Activity.update` / `Activity.end` Sendable workaround to the single awaited framework call using `nonisolated(unsafe)`.
  - does not change hydration completion state semantics.
- `CompanionNotificationScheduler.swift`
  - removes manual checked-continuation wrappers around UserNotifications.
  - uses the native async APIs for notification settings, pending requests, and add(request).

Validation performed in this environment:

- `swift test --package-path JomadoCore`: 25/25 passed.
- No manual `withCheckedContinuation` remains in `CompanionNotificationScheduler.swift`.
- Full Apple/Xcode build still needs GitHub Actions/macOS because ActivityKit, AlarmKit, WidgetKit and UserNotifications are Apple-platform frameworks.

Hydration invariant remains unchanged:
Silence, dismiss, open, acknowledge, or snooze do not mark hydration completed. Only the explicit completion action does.
