# Iteration 16 status

Closed an analytics correctness gap in the hydration MVP.

- Completion rate now uses resolved outcomes only (completed / [completed + skipped + expired]).
- Open reminders remain visible as open and never depress or inflate completion rate.
- Insights now surfaces Open and Skipped counts alongside Completed and Missed.
- Insights explicitly states that silenced, dismissed, snoozed, or otherwise unresolved reminders never count as completion.
- Preserved local-only analytics: no hydration analytics upload was added.
- Preserved prior scheduling, AlarmKit reconciliation, permission diagnostics, content validation/fallback, Today open-state visibility, and completion semantics.

Validation in this environment: JomadoCore 24/24 tests pass; modified Insights/Analytics sources parse with Swift. Full SwiftUI/ActivityKit/WidgetKit/AlarmKit type-check still requires Xcode/macOS CI.

Repository integration attempt: GitHub repository metadata reports push/admin permission, but branch creation still returns 403 `Resource not accessible by integration`; therefore this cumulative source remains packaged for manual/authorized import rather than modifying main.
