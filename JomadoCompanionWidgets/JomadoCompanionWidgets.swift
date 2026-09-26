import ActivityKit
import SwiftUI
import WidgetKit

@main
struct JomadoCompanionWidgetBundle: WidgetBundle {
    var body: some Widget {
        CompanionLiveActivityWidget()
    }
}

struct CompanionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionActivityAttributes.self) { context in
            CompanionLockScreenView(state: context.state)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    JomadoMascot(state: context.state, size: 48)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline)
                        Text(context.state.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RelativeDueLabel(date: context.state.scheduledAt)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label("Tap to open Jomado · task stays open until you complete it", systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                JomadoMascot(state: context.state, size: 26)
            } compactTrailing: {
                RelativeDueLabel(date: context.state.scheduledAt, compact: true)
            } minimal: {
                JomadoMascot(state: context.state, size: 23)
            }
            .keylineTint(palette(for: context.state).accent)
        }
    }
}

private struct CompanionLockScreenView: View {
    let state: CompanionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            JomadoMascot(state: state, size: 78)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    RelativeDueLabel(date: state.scheduledAt)
                }

                Text(state.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Image(systemName: "hand.tap.fill")
                    Text("Open Jomado · \(state.completionLabel)")
                }
                .font(.caption.bold())
                .foregroundStyle(palette(for: state).accent)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [palette(for: state).accent.opacity(0.22), palette(for: state).secondary.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jomado reminder. \(state.title). \(state.message). Open Jomado to complete the task.")
    }
}

/// A tiny vector mascot intentionally drawn with SwiftUI primitives so it remains
/// crisp on the Lock Screen, Dynamic Island and Always-On Display without loading
/// an animation framework. Mood changes are driven by reminder state; iOS animates
/// Live Activity state transitions when the system permits them.
private struct JomadoMascot: View {
    let state: CompanionActivityAttributes.ContentState
    let size: CGFloat

    private var mood: MascotMood { MascotMood(rawValue: state.expressionRaw) ?? .waiting }
    private var colors: MascotPalette { palette(for: state) }

    var body: some View {
        ZStack {
            mascotBody
            face
            if mood == .celebrating || mood == .proud { celebrationMarks }
            if mood == .sleepy { sleepyMark }
            if mood == .urgent { urgencyMark }
        }
        .frame(width: size, height: size)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityHidden(true)
    }

    private var mascotBody: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [colors.secondary, colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: colors.accent.opacity(0.28), radius: size * 0.10, y: size * 0.05)

            Circle()
                .fill(.white.opacity(0.26))
                .frame(width: size * 0.28, height: size * 0.18)
                .blur(radius: size * 0.015)
                .offset(x: -size * 0.18, y: -size * 0.20)

            Image(systemName: mascotSymbol)
                .font(.system(size: size * 0.24, weight: .black))
                .foregroundStyle(.white.opacity(0.20))
                .offset(y: -size * 0.23)
        }
    }

    private var face: some View {
        VStack(spacing: size * 0.075) {
            HStack(spacing: size * 0.19) {
                eye
                eye
            }
            mouth
        }
        .offset(y: size * 0.08)
        .overlay(alignment: .center) {
            if mood == .pouty || mood == .concerned {
                HStack(spacing: size * 0.48) {
                    Circle().fill(.pink.opacity(0.55)).frame(width: size * 0.10, height: size * 0.055)
                    Circle().fill(.pink.opacity(0.55)).frame(width: size * 0.10, height: size * 0.055)
                }
                .offset(y: size * 0.16)
            }
        }
    }

    private var eye: some View {
        Group {
            if mood == .sleepy {
                Capsule().fill(.white).frame(width: size * 0.10, height: max(2, size * 0.025))
            } else if mood == .celebrating {
                Image(systemName: "chevron.down")
                    .font(.system(size: size * 0.09, weight: .black))
                    .foregroundStyle(.white)
            } else {
                ZStack {
                    Circle().fill(.white)
                    Circle().fill(.black.opacity(0.68)).frame(width: size * 0.035, height: size * 0.045)
                        .offset(y: mood == .concerned ? size * 0.012 : 0)
                }
                .frame(width: size * 0.105, height: size * 0.125)
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .celebrating, .proud, .hello:
            Capsule().fill(.white).frame(width: size * 0.25, height: size * 0.065)
        case .pouty, .concerned:
            Image(systemName: "chevron.up")
                .font(.system(size: size * 0.13, weight: .black))
                .foregroundStyle(.white)
        case .urgent:
            Circle().fill(.white).frame(width: size * 0.10, height: size * 0.10)
        case .sleepy:
            Capsule().fill(.white.opacity(0.9)).frame(width: size * 0.12, height: size * 0.035)
        default:
            Capsule().fill(.white).frame(width: size * 0.18, height: size * 0.045)
        }
    }

    private var celebrationMarks: some View {
        ZStack {
            Image(systemName: "sparkle").offset(x: -size * 0.42, y: -size * 0.28)
            Image(systemName: "sparkles").offset(x: size * 0.40, y: -size * 0.30)
        }
        .font(.system(size: size * 0.15, weight: .bold))
        .foregroundStyle(colors.accent)
    }

    private var sleepyMark: some View {
        Text("z")
            .font(.system(size: size * 0.18, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .offset(x: size * 0.34, y: -size * 0.34)
    }

    private var urgencyMark: some View {
        Text("!")
            .font(.system(size: size * 0.20, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .offset(x: size * 0.34, y: -size * 0.34)
    }

    private var mascotSymbol: String {
        switch state.mascotRaw {
        case "sparky": return "bolt.fill"
        case "pip": return "sparkles"
        default: return "drop.fill"
        }
    }
}

private struct RelativeDueLabel: View {
    let date: Date
    var compact = false

    var body: some View {
        Text(date, style: .relative)
            .font(compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private enum MascotMood: String {
    case idle, hello, waiting, hopeful, pouty, concerned, urgent, sleepy, proud, celebrating
}

private struct MascotPalette {
    let accent: Color
    let secondary: Color
}

private func palette(for state: CompanionActivityAttributes.ContentState) -> MascotPalette {
    switch state.mascotRaw {
    case "sparky":
        return MascotPalette(accent: urgencyTint(state.urgencyLevel, base: .orange), secondary: .yellow)
    case "pip":
        return MascotPalette(accent: urgencyTint(state.urgencyLevel, base: .purple), secondary: .pink)
    default:
        return MascotPalette(accent: urgencyTint(state.urgencyLevel, base: .cyan), secondary: .blue)
    }
}

private func urgencyTint(_ urgency: Int, base: Color) -> Color {
    switch urgency {
    case 0: return base
    case 1: return .yellow
    case 2: return .orange
    default: return .red
    }
}
