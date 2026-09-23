import SwiftUI
import JomadoCore

struct ContentPreferencesView: View {
    @State private var disabledStrategies: Set<Strategy> = []
    @State private var disabledMascots: Set<MascotID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder styles") {
                    ForEach(Strategy.allCases, id: \.self) { strategy in Toggle(strategy.rawValue.displayName, isOn: binding(strategy)) }
                }
                Section("Companions") {
                    ForEach(MascotID.allCases, id: \.self) { mascot in Toggle(mascot.rawValue.capitalized, isOn: mascotBinding(mascot)) }
                }
                Section { Text("Jomado keeps a small exploration rate so it can occasionally test different styles instead of trapping you in one pattern.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Your vibe").onAppear(perform: load).onChange(of: disabledStrategies) { _,_ in save() }.onChange(of: disabledMascots) { _,_ in save() }
        }
    }
    private func binding(_ s: Strategy) -> Binding<Bool> { Binding(get: { !disabledStrategies.contains(s) }, set: { $0 ? disabledStrategies.remove(s) : disabledStrategies.insert(s) }) }
    private func mascotBinding(_ m: MascotID) -> Binding<Bool> { Binding(get: { !disabledMascots.contains(m) }, set: { $0 ? disabledMascots.remove(m) : disabledMascots.insert(m) }) }
    private func load() {
        disabledStrategies = Set((UserDefaults.standard.string(forKey: "disabledStrategies") ?? "").split(separator: ",").compactMap { Strategy(rawValue: String($0)) })
        disabledMascots = Set((UserDefaults.standard.string(forKey: "disabledMascots") ?? "").split(separator: ",").compactMap { MascotID(rawValue: String($0)) })
    }
    private func save() {
        UserDefaults.standard.set(disabledStrategies.map(\.rawValue).joined(separator: ","), forKey: "disabledStrategies")
        UserDefaults.standard.set(disabledMascots.map(\.rawValue).joined(separator: ","), forKey: "disabledMascots")
    }
}

private extension String { var displayName: String { replacingOccurrences(of: "RPG", with: " RPG").replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized } }
