import SwiftUI
import UIKit
import JomadoCore

struct AddScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var runtime: JomadoRuntime
    let routine: HydrationScheduleEntity?

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var intervalMinutes: Int
    @State private var weekdays: Set<Int>
    @State private var deliveryMode: ReminderDeliveryMode
    @State private var saving = false


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
        _deliveryMode = State(initialValue: routine?.deliveryMode ?? .companion)
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

                Section {
                    Picker("Delivery", selection: $deliveryMode) {
                        ForEach(ReminderDeliveryMode.allCases, id: \.self) { mode in
                            Label(
                                mode.title,
                                systemImage: mode == .companion ? "message.badge.waveform.fill" : "alarm.fill"
                            )
                            .tag(mode)
                        }
                    }
                } header: {
                    Text("Reminder style")
                } footer: {
                    Text(deliveryMode == .companion
                        ? "Companion uses Lock Screen notifications and the Jomado Live Activity. Dismissing it never completes the task."
                        : "Alarm uses AlarmKit for a prominent system alarm. Silencing still never completes the task.")
                }

                Section {
                    HStack {
                        Label(deliveryPermissionTitle, systemImage: deliveryPermissionIcon)
                        Spacer()
                        Text(deliveryPermissionState).foregroundStyle(deliveryPermissionColor)
                    }
                    if deliveryNeedsPermissionAction {
                        Button(deliveryPermissionActionTitle) { handlePermissionAction() }
                    }
                } header: {
                    Text("Delivery readiness")
                } footer: {
                    Text(deliveryPermissionDetail)
                }

                Section {
                    Stepper(
                        value: $intervalMinutes,
                        in: HydrationRoutineConfiguration.minimumIntervalMinutes...HydrationRoutineConfiguration.maximumIntervalMinutes,
                        step: 15
                    ) {
                        LabeledContent("Remind me", value: intervalLabel(intervalMinutes))
                    }
                    .accessibilityValue(intervalLabel(intervalMinutes))

                    LabeledContent(
                        deliveryMode == .companion ? "Generated reminders" : "Generated alarms",
                        value: "\(configuration.alarmCount)"
                    )
                } header: {
                    Text("Cadence")
                } footer: {
                    Text("Choose any 15-minute increment from 15 minutes to 6 hours. The preview below shows every generated time before you save.")
                }

                Section("Repeat") {
                    HStack(spacing: 7) {
                        ForEach(1...7, id: \.self) { day in
                            dayButton(day)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    HStack {
                        Button("Every day") { weekdays = Set(1...7) }
                        Spacer()
                        Button("Weekdays") { weekdays = Set(2...6) }
                        Spacer()
                        Button("Weekend") { weekdays = [1, 7] }
                    }
                    .font(.footnote)
                }

                if validationMessage == nil {
                    Section {
                        ForEach(configuration.generatedMinutes, id: \.self) { minuteOfDay in
                            LabeledContent(alarmTimeText(minuteOfDay), value: daySummary)
                        }
                    } header: {
                        Text(deliveryMode == .companion ? "Reminder preview" : "Alarm preview")
                    } footer: {
                        Text(deliveryMode == .companion
                            ? "\(configuration.alarmCount) companion reminder\(configuration.alarmCount == 1 ? "" : "s") will be generated for the selected days."
                            : "\(configuration.alarmCount) recurring system alarm\(configuration.alarmCount == 1 ? "" : "s") will be kept in sync with this routine.")
                    }
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Label {
                        Text("Dismiss, silence, or close only acknowledges the reminder surface. You must still tap **I drank water** in Jomado to complete the task.")
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

    private var deliveryPermissionTitle: String { deliveryMode == .companion ? "Companion notifications" : "Alarm access" }
    private var deliveryPermissionState: String { deliveryMode == .companion ? runtime.companionDiagnostics.authorization.title : runtime.alarmDiagnostics.authorization.title }
    private var deliveryPermissionIcon: String { deliveryMode == .companion ? runtime.companionDiagnostics.authorization.systemImage : runtime.alarmDiagnostics.authorization.systemImage }
    private var deliveryPermissionColor: Color {
        let denied = deliveryMode == .companion ? runtime.companionDiagnostics.authorization == .denied : runtime.alarmDiagnostics.authorization == .denied
        let authorized = deliveryMode == .companion ? runtime.companionDiagnostics.authorization == .authorized : runtime.alarmDiagnostics.authorization == .authorized
        return denied ? .red : (authorized ? .green : .secondary)
    }
    private var deliveryNeedsPermissionAction: Bool { deliveryMode == .companion ? runtime.companionDiagnostics.authorization != .authorized : runtime.alarmDiagnostics.authorization != .authorized }
    private var deliveryPermissionActionTitle: String {
        let denied = deliveryMode == .companion ? runtime.companionDiagnostics.authorization == .denied : runtime.alarmDiagnostics.authorization == .denied
        return denied ? "Open iOS Settings" : "Allow access"
    }
    private var deliveryPermissionDetail: String {
        if deliveryMode == .companion {
            switch runtime.companionDiagnostics.authorization {
            case .authorized: return "Ready. iOS can deliver companion reminders while Jomado is closed."
            case .notDetermined: return "Notification permission is required for reminders to appear while Jomado is closed. You can grant it now or when saving."
            case .denied: return "Notifications are blocked in iOS Settings. The routine can be saved, but companion reminders will not appear until access is restored."
            }
        }
        switch runtime.alarmDiagnostics.authorization {
        case .authorized: return "Ready. AlarmKit can deliver prominent system alarms for this routine."
        case .notDetermined: return "Alarm permission is required before generated alarms can ring."
        case .denied: return "Alarm access is blocked in iOS Settings. The routine can be saved, but its generated alarms cannot ring until access is restored."
        }
    }
    private func handlePermissionAction() {
        let denied = deliveryMode == .companion ? runtime.companionDiagnostics.authorization == .denied : runtime.alarmDiagnostics.authorization == .denied
        if denied {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; openURL(url); return
        }
        Task {
            if deliveryMode == .companion { _ = await runtime.requestCompanionAuthorization() }
            else { _ = await runtime.requestAlarmAuthorization() }
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

    private var daySummary: String {
        if weekdays.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted()
            .compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }
            .joined(separator: " · ")
    }

    private func alarmTimeText(_ minuteOfDay: Int) -> String {
        let date = Calendar.current.date(
            from: DateComponents(hour: minuteOfDay / 60, minute: minuteOfDay % 60)
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
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
                weekdays: weekdays.sorted(),
                deliveryMode: deliveryMode
            )
            saving = false
            if saved { dismiss() }
        }
    }

    private static func time(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }
}
