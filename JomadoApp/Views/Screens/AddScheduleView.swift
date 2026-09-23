import SwiftUI

struct AddScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var runtime: JomadoRuntime
    @State private var time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") { DatePicker("Drink water", selection: $time, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden() }
                Section("Repeat") {
                    HStack { ForEach(1...7, id: \.self) { day in dayButton(day) } }
                }
                Section { Text("Stopping the system alarm only acknowledges it. The hydration task remains pending until you mark it complete.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Water reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving || weekdays.isEmpty) }
            }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let title = String(Calendar.current.veryShortWeekdaySymbols[day-1])
        return Button { if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) } } label: {
            Text(title).font(.caption.bold()).frame(width: 34, height: 34).background(weekdays.contains(day) ? Color.cyan : Color.secondary.opacity(0.12), in: Circle()).foregroundStyle(weekdays.contains(day) ? .white : .primary)
        }.buttonStyle(.plain)
    }
    private func save() {
        saving = true
        let comps = Calendar.current.dateComponents([.hour,.minute], from: time)
        Task { await runtime.createSchedule(hour: comps.hour ?? 9, minute: comps.minute ?? 0, weekdays: weekdays.sorted()); saving = false; dismiss() }
    }
}
