import SwiftUI
import JomadoCore

struct AddScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var runtime: JomadoRuntime
    let routine: HydrationScheduleEntity?

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var intervalMinutes: Int
    @State private var weekdays: Set<Int>
    @State private var saving = false

    private let intervalOptions = [30, 45, 60, 90, 120, 180]

    init(runtime: JomadoRuntime, routine: HydrationScheduleEntity? = nil) {
        self.runtime = runtime
        self.routine = routine
        _startTime = State(initialValue: Self.time(
            hour: routine?.hour ?? 8,
            minute: routine?.minute ?? 0
        ))
        _endTime = State(initialValue: Self.time(
            hour: routine?.resolvedEndHour ?? 20,
            minute: routine?.resolvedEndMinute ?? 0
        ))
        _intervalMinutes = State(initialValue: routine?.resolvedIntervalMinutes ?? 60)
        _weekdays = State(initialValue: Set(routine?.weekdays ?? Array(1...7)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Daily window")
                } footer: {
                    Text("Times stay aligned to local wall-clock time when you travel or daylight saving time changes.")
                }

                Section("Cadence") {
                    Picker("Remind me", selection: $intervalMinutes) {
                        ForEach(intervalOptions, id: \.self) { minutes in
                            Text(intervalLabel(minutes)).tag(minutes)
                        }
                    }
                    LabeledContent("Generated alarms", value: "\(configuration.alarmCount)")
                }

                Section("Repeat") {
                    HStack(spacing: 7) {
                        ForEach(1...7, id: \.self) { day in
                            dayButton(day)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Label {
                        Text("Silencing a system alarm acknowledges the interruption only. You must still tap **I drank water** in Jomado to complete the task.")
                    } icon: {
                        Image(systemName: "checkmark.circle.badge.xmark")
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .navigationTitle(routine == nil ? "Set up hydration" : "Edit hydration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(saving || validationMessage != nil)
                }
            }
        }
    }

    private var configuration: HydrationRoutineConfiguration {
        let start = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let end = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        return HydrationRoutineConfiguration(
            startMinuteOfDay: (start.hour ?? 0) * 60 + (start.minute ?? 0),
            endMinuteOfDay: (end.hour ?? 0) * 60 + (end.minute ?? 0),
            intervalMinutes: intervalMinutes,
            weekdays: weekdays.sorted()
        )
    }

    private var validationMessage: String? {
        do {
            try configuration.validate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let selected = weekdays.contains(day)
        return Button {
            if selected { weekdays.remove(day) } else { weekdays.insert(day) }
        } label: {
            Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                .font(.caption.bold())
                .frame(width: 36, height: 36)
                .background(selected ? Color.cyan : Color.secondary.opacity(0.12), in: Circle())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "Every \(minutes) minutes" }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "Every \(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "Every \(minutes / 60) hr \(minutes % 60) min"
    }

    private func save() {
        saving = true
        let start = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let end = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        Task {
            let saved = await runtime.saveRoutine(
                routine,
                startHour: start.hour ?? 8,
                startMinute: start.minute ?? 0,
                endHour: end.hour ?? 20,
                endMinute: end.minute ?? 0,
                intervalMinutes: intervalMinutes,
                weekdays: weekdays.sorted()
            )
            saving = false
            if saved { dismiss() }
        }
    }

    private static func time(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }
}
