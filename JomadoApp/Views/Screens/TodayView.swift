import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \HydrationScheduleEntity.createdAt) private var schedules: [HydrationScheduleEntity]
    @Query(sort: \ReminderOccurrenceEntity.scheduledAt, order: .reverse) private var occurrences: [ReminderOccurrenceEntity]
    @ObservedObject var runtime: JomadoRuntime
    @State private var addSchedule = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if schedules.isEmpty { emptyCard } else { scheduleList }
                    progressCard
                }.padding()
            }
            .navigationTitle("Jomado")
            .toolbar { Button { addSchedule = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $addSchedule) { AddScheduleView(runtime: runtime) }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            MascotView(mascot: .momo, expression: .hello).scaleEffect(0.46).frame(width: 78, height: 78)
            VStack(alignment: .leading) {
                Text("Today's tiny promises").font(.title2.bold())
                Text("Silencing an alarm never counts as completion.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var emptyCard: some View {
        ContentUnavailableView("No water reminders yet", systemImage: "drop.circle", description: Text("Add your first hydration time. Jomado will keep the task open until you act."))
            .frame(maxWidth: .infinity).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var scheduleList: some View {
        VStack(spacing: 10) {
            ForEach(schedules) { schedule in
                HStack {
                    Image(systemName: "alarm.fill").foregroundStyle(.cyan)
                    VStack(alignment: .leading) { Text(schedule.timeText).font(.title3.bold()); Text(dayText(schedule.weekdays)).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(role: .destructive) { runtime.deleteSchedule(schedule) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var progressCard: some View {
        let completed = occurrences.filter { $0.completedAt != nil && Calendar.current.isDateInToday($0.scheduledAt) }.count
        let skipped = occurrences.filter { $0.skippedAt != nil && Calendar.current.isDateInToday($0.scheduledAt) }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("Today").font(.headline)
            HStack { stat("Completed", "\(completed)", "checkmark.circle.fill", .green); stat("Skipped", "\(skipped)", "xmark.circle.fill", .orange) }
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func stat(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading) { Image(systemName: icon).foregroundStyle(color); Text(value).font(.title.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func dayText(_ days: [Int]) -> String {
        if days.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.compactMap { (1...7).contains($0) ? symbols[$0-1] : nil }.joined(separator: " · ")
    }
}
