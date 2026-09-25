import SwiftUI
import SwiftData

@main
struct JomadoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(for: [
                HydrationScheduleEntity.self,
                HydrationAlarmEntity.self,
                ReminderOccurrenceEntity.self,
                ContentExposureEntity.self,
                AlarmEventReceiptEntity.self
            ])
    }
}
