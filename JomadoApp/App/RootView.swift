import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @StateObject private var runtime = JomadoRuntime()

    var body: some View {
        Group {
            if hasOnboarded {
                TabView {
                    TodayView(runtime: runtime).tabItem { Label("Today", systemImage: "drop.fill") }
                    InsightsView(runtime: runtime).tabItem { Label("Insights", systemImage: "chart.bar.fill") }
                    ContentPreferencesView().tabItem { Label("Vibe", systemImage: "sparkles") }
                    SettingsView(runtime: runtime).tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
            } else { OnboardingView(runtime: runtime) }
        }
        .task { await runtime.attach(modelContext: modelContext) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await runtime.refreshSystemState() }
            }
        }
        .fullScreenCover(item: $runtime.activeReminder) { _ in ReminderExperienceView(runtime: runtime) }
        .alert("Jomado", isPresented: Binding(get: { runtime.lastError != nil }, set: { if !$0 { runtime.lastError = nil } })) { Button("OK", role: .cancel) {} } message: { Text(runtime.lastError ?? "") }
    }
}
