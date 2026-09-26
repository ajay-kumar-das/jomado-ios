import SwiftUI
import JomadoCore

struct MascotView: View {
    let mascot: MascotID
    let expression: MascotExpression
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    private var symbol: String {
        switch mascot { case .momo: "drop.fill"; case .sparky: "bolt.fill"; case .pip: "sparkles" }
    }
    private var accent: Color {
        switch mascot { case .momo: .cyan; case .sparky: .orange; case .pip: .purple }
    }

    var body: some View {
        ZStack {
            Circle().fill(accent.gradient).frame(width: 156, height: 156).shadow(color: accent.opacity(0.25), radius: 24, y: 12)
            Image(systemName: symbol).font(.system(size: 58, weight: .bold)).foregroundStyle(.white)
            face
        }
        .scaleEffect(reduceMotion ? 1 : (bounce ? 1.04 : 0.97))
        .rotationEffect(.degrees(reduceMotion ? 0 : (expression == .urgent && bounce ? 2 : 0)))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: expression == .urgent ? 0.35 : 0.9).repeatForever(autoreverses: true),
            value: bounce
        )
        .onAppear { bounce = !reduceMotion }
        .onChange(of: reduceMotion) { _, enabled in bounce = !enabled }
        .accessibilityLabel("\(mascot.rawValue) mascot, \(expression.rawValue)")
    }

    private var face: some View {
        VStack(spacing: 12) {
            HStack(spacing: 36) {
                Circle().fill(.white).frame(width: 10, height: expression == .concerned ? 7 : 12)
                Circle().fill(.white).frame(width: 10, height: expression == .concerned ? 7 : 12)
            }
            Capsule().fill(.white).frame(width: expression == .celebrating ? 34 : 22, height: 6)
                .rotationEffect(.degrees(expression == .concerned ? 180 : 0))
        }.offset(y: 14)
    }
}
