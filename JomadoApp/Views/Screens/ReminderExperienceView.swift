import SwiftUI
import JomadoCore

struct ReminderExperienceView: View {
    @ObservedObject var runtime: JomadoRuntime
    @State private var now = Date()
    @State private var showSkip = false
    let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        if let reminder = runtime.activeReminder {
            ZStack {
                UrgencyBackground(stage: reminder.urgency)
                ScrollView {
                    VStack(spacing: 24) {
                        HStack {
                            Label(stageLabel(reminder.urgency), systemImage: "drop.fill").font(.subheadline.bold())
                            Spacer()
                            if reminder.isSimulation {
                                Text("SIMULATION")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.purple.opacity(0.14), in: Capsule())
                            }
                            Text(delayText(reminder)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        MascotView(mascot: reminder.content.mascot.id, expression: reminder.content.mascot.expression)
                            .padding(.top, 24)
                        VStack(spacing: 10) {
                            Text(reminder.content.message.title).font(.system(size: 34, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                            Text(reminder.content.message.body).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .contentTransition(.numericText())

                        VStack(spacing: 12) {
                            Button {
                                runtime.complete()
                            } label: {
                                Label("I drank water", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.borderedProminent).controlSize(.large)

                            Label("Alarm silence only acknowledges the alert — this task stays open.", systemImage: "speaker.slash.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Skip this one", role: .destructive) { showSkip = true }.font(.footnote)
                        }

                        HStack(spacing: 18) {
                            feedback("heart.fill", 2, "Loved")
                            feedback("hand.thumbsup.fill", 1, "Good")
                            feedback("minus.circle", 0, "Meh")
                            feedback("hand.thumbsdown.fill", -1, "Not mine")
                        }.padding(.top, 8)
                    }.padding(24)
                }
            }
            .onReceive(timer) { _ in
                now = Date()
                let newStage = UrgencyPolicy.stage(delayMinutes: reminder.delayMinutes)
                if newStage != reminder.content.stage { runtime.refreshContentForCurrentUrgency() }
            }
            .confirmationDialog("Skip this reminder?", isPresented: $showSkip) {
                Button("Skip", role: .destructive) { runtime.skip() }
                Button("Keep it open", role: .cancel) { }
            }
            .interactiveDismissDisabled()
        }
    }

    private func feedback(_ symbol: String, _ value: Int, _ label: String) -> some View {
        Button { runtime.feedback(value) } label: { VStack(spacing: 5) { Image(systemName: symbol); Text(label).font(.caption2) } }.buttonStyle(.plain)
    }
    private func stageLabel(_ stage: UrgencyStage) -> String { switch stage { case .normal: "Water time"; case .lightOverdue: "Waiting for you"; case .mediumOverdue: "Overdue"; case .redZone: "Red zone" } }
    private func delayText(_ reminder: ActiveReminder) -> String { reminder.delayMinutes == 0 ? "now" : "\(reminder.delayMinutes)m late" }
}
