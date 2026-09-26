import SwiftUI
import SwiftData

@main
struct JomadoApp: App {
    @UIApplicationDelegateAdaptor(JomadoAppDelegate.self) private var appDelegate

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
