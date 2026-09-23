import SwiftUI
import JomadoCore

struct UrgencyBackground: View {
    let stage: UrgencyStage
    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }
    private var colors: [Color] {
        switch stage {
        case .normal: [.cyan.opacity(0.18), .mint.opacity(0.10), .white]
        case .lightOverdue: [.yellow.opacity(0.24), .orange.opacity(0.09), .white]
        case .mediumOverdue: [.orange.opacity(0.30), .red.opacity(0.08), .white]
        case .redZone: [.red.opacity(0.32), .pink.opacity(0.10), .white]
        }
    }
}
