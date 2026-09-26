import SwiftUI
import SwiftData
import JomadoCore

struct TodayView: View {
    @Query(sort: \HydrationScheduleEntity.createdAt) private var routines: [HydrationScheduleEntity]
    @Query private var alarms: [HydrationAlarmEntity]
    @Query(sort: \ReminderOccurrenceEntity.scheduledAt, order: .reverse) private var occurrences: [ReminderOccurrenceEntity]
    @ObservedObject var runtime: JomadoRuntime

    @State private var editorPresented = false
    @State private var editingRoutine: HydrationScheduleEntity?
    @State private var routineToDelete: HydrationScheduleEntity?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if runtime.companionDiagnostics.needsAttention && routines.contains(where: { $0.enabled && $0.deliveryMode.usesCompanionNotification }) {
                        companionStatusCard
                    }
                    if runtime.alarmDiagnostics.needsAttention && routines.contains(where: { $0.enabled && $0.deliveryMode.usesAlarmKit }) {
                        alarmStatusCard
                    }
                    if routines.isEmpty { emptyCard } else { routineList }
                    todayProgressCard
                }
                .padding()
            }
            .background(Color.cyan.opacity(0.04))
            .navigationTitle("Today")
            .toolbar {
                Button {
                    editingRoutine = nil
                    editorPresented = true
                } label: {
                    Label("Add hydration routine", systemImage: "plus")
                }
            }
            .sheet(isPresented: $editorPresented) {
                AddScheduleView(runtime: runtime, routine: editingRoutine)
            }
            .confirmationDialog(
                "Delete this hydration routine?",
                isPresented: Binding(
                    get: { routineToDelete != nil },
                    set: { if !$0 { routineToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete routine", role: .destructive) {
                    guard let routine = routineToDelete else { return }
                    Task { await runtime.deleteRoutine(routine) }
                    routineToDelete = nil
                }
                Button("Cancel", role: .cancel) { routineToDelete = nil }
            } message: {
                Text("Its generated system alarms will also be removed.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            MascotView(mascot: .momo, expression: .hello)
                .scaleEffect(0.46)
                .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your hydration loop")
                    .font(.title2.bold())
                if let nextReminder {
                    Text("Next reminder: \(nextReminder.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set a window and Jomado will generate your companion reminders.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var companionStatusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: runtime.companionDiagnostics.authorization.systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Companion reminders need attention").font(.headline)
                Text(runtime.companionDiagnostics.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
    }

    private var alarmStatusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: runtime.alarmDiagnostics.authorization.systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Alarms need attention").font(.headline)
                Text(runtime.alarmDiagnostics.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "drop.circle")
                .font(.system(size: 42))
                .foregroundStyle(.cyan)
            Text("No hydration routine yet").font(.headline)
            Text("Choose a daily window, interval, and weekdays. Companion mode keeps the experience gentle on the Lock Screen; Alarm mode stays available when you want something stronger.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Set up hydration") {
                editingRoutine = nil
                editorPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var routineList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Routines").font(.headline)
            ForEach(routines) { routine in
                routineCard(routine)
            }
        }
    }

    private func routineCard(_ routine: HydrationScheduleEntity) -> some View {
        let generatedCount = alarms.filter { $0.routineID == routine.id }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(routine.startTimeText) – \(routine.endTimeText)")
                        .font(.title3.bold())
                    Text("\(routine.intervalText) · \(dayText(routine.weekdays))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Routine enabled", isOn: Binding(
                    get: { routine.enabled },
                    set: { enabled in
                        Task { await runtime.setRoutineEnabled(routine, enabled: enabled) }
                    }
                ))
                .labelsHidden()
            }

            HStack {
                Label("\(routine.configuration.alarmCount) planned", systemImage: "clock")
                Spacer()
                if routine.deliveryMode.usesAlarmKit {
                    Label("\(generatedCount) alarms", systemImage: "alarm.fill")
                } else {
                    Label("Companion", systemImage: "message.badge.waveform.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                Button("Edit") {
                    editingRoutine = routine
                    editorPresented = true
                }
                Spacer()
                Button("Delete", role: .destructive) { routineToDelete = routine }
            }
            .font(.subheadline)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .opacity(routine.enabled ? 1 : 0.65)
    }

    private var todayProgressCard: some View {
        let real = occurrences.filter {
            !$0.isSimulation && Calendar.current.isDateInToday($0.scheduledAt)
        }
        let completed = real.filter { $0.completedAt != nil }.count
        let skipped = real.filter { $0.skippedAt != nil }.count
        let missed = real.filter { $0.expiredAt != nil }.count
        let open = real.filter { occurrence in
            occurrence.completedAt == nil &&
            occurrence.skippedAt == nil &&
            occurrence.expiredAt == nil &&
            [.alarming, .acknowledged, .overdue, .actionStarted].contains(occurrence.state)
        }.count
        let resolved = completed + skipped + missed
        let completionRate = resolved == 0 ? nil : Int((Double(completed) / Double(resolved) * 100).rounded())
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                Text("\(plannedToday) planned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                stat("Completed", "\(completed)", "checkmark.circle.fill", .green)
                stat("Open", "\(open)", "drop.circle.fill", .cyan)
                stat("Skipped", "\(skipped)", "forward.end.circle.fill", .orange)
                stat("Missed", "\(missed)", "clock.badge.xmark.fill", .red)
            }
            if let completionRate {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("\(completionRate)% of resolved reminders completed today")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            } else if open > 0 {
                Text("You have an open hydration reminder. It stays open until you complete, skip, or it expires.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Label("Silencing, dismissing, or snoozing never counts as completion.", systemImage: "speaker.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var nextReminder: Date? {
        routines
            .filter(\.enabled)
            .compactMap { $0.configuration.nextOccurrence(after: Date(), calendar: .autoupdatingCurrent) }
            .min()
    }

    private var plannedToday: Int {
        routines.filter(\.enabled).reduce(0) { total, routine in
            total + routine.configuration.occurrences(on: Date(), calendar: .autoupdatingCurrent).count
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title2.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayText(_ days: [Int]) -> String {
        if days.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }
            .joined(separator: " · ")
    }
}
