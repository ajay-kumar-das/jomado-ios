import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @ObservedObject var runtime: JomadoRuntime
    @State private var requestingAccess = false
    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            MascotView(mascot: .momo, expression: .hello)
            VStack(spacing: 10) {
                Text("Meet Jomado").font(.largeTitle.bold())
                Text("A gentle hydration companion that keeps the task separate from the alarm.").font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                Label("A start-to-end hydration routine", systemImage: "calendar.badge.clock")
                Label("Prominent AlarmKit reminders", systemImage: "alarm.fill")
                Label("Private, on-device insights", systemImage: "lock.fill")
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
            Button(requestingAccess ? "Requesting…" : "Enable alarms & continue") {
                requestingAccess = true
                Task {
                    _ = await runtime.requestAlarmAuthorization()
                    requestingAccess = false
                    hasOnboarded = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(requestingAccess)
            Button("Continue without alarms") { hasOnboarded = true }.font(.footnote)
            Text("Silencing or stopping an alarm never marks water as drunk.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }.padding(28).background(LinearGradient(colors: [.cyan.opacity(0.18), .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}
