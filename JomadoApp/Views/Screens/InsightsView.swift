import SwiftUI
import JomadoCore

struct InsightsView: View {
    @ObservedObject var runtime: JomadoRuntime
    @State private var refresh = UUID()
    var body: some View {
        NavigationStack {
            ScrollView {
                let s = runtime.summary()
                VStack(spacing: 16) {
                    metric("Completion", percent(s.completionRate), "checkmark.seal.fill")
                    HStack { metric("≤ 2 min", percent(s.within2Minutes), "bolt.fill"); metric("≤ 5 min", percent(s.within5Minutes), "timer") }
                    HStack { metric("≤ 15 min", percent(s.within15Minutes), "clock"); metric("Median", latency(s.medianLatency), "chart.line.uptrend.xyaxis") }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Strategies").font(.headline)
                        ForEach(runtime.strategyStats(), id: \.0.rawValue) { strategy, p in
                            HStack { Text(display(strategy.rawValue)); Spacer(); Text("\(Int(p.completionRate * 100))% · \(p.exposures) shown").foregroundStyle(.secondary) }
                        }
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                }.padding()
            }.navigationTitle("Insights")
        }
    }
    private func metric(_ name: String, _ value: String, _ symbol: String) -> some View { VStack(alignment: .leading, spacing: 8) { Image(systemName: symbol).foregroundStyle(.cyan); Text(value).font(.title2.bold()); Text(name).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20)) }
    private func percent(_ v: Double) -> String { "\(Int(v * 100))%" }
    private func latency(_ v: TimeInterval?) -> String { guard let v else { return "—" }; let m = Int(v/60); let s = Int(v)%60; return "\(m)m \(s)s" }
    private func display(_ raw: String) -> String { raw.replacingOccurrences(of: "RPG", with: " RPG").replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }
}
