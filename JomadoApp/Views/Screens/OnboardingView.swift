import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @ObservedObject var runtime: JomadoRuntime
    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            MascotView(mascot: .momo, expression: .hello)
            VStack(spacing: 10) {
                Text("Meet Jomado").font(.largeTitle.bold())
                Text("A cute accountability companion that separates dismissing a reminder from actually doing the thing.").font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                Label("Prominent water alarms", systemImage: "alarm.fill")
                Label("Different messages and mascots", systemImage: "sparkles")
                Label("Local behavioral learning", systemImage: "lock.fill")
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
            Button("Enable alarms & continue") {
                Task { _ = await runtime.alarmScheduler.requestAuthorization(); hasOnboarded = true }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("Continue without alarms") { hasOnboarded = true }.font(.footnote)
            Spacer()
        }.padding(28).background(LinearGradient(colors: [.cyan.opacity(0.18), .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}
