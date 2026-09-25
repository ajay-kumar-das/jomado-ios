import SwiftUI
import JomadoCore

struct ContentPreferencesView: View {
    @State private var disabledStrategies: Set<Strategy> = []
    @State private var disabledMascots: Set<MascotID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder styles") {
                    ForEach(Strategy.allCases, id: \.self) { strategy in
                        Toggle(
                            strategy.rawValue.displayName,
                            isOn: binding(strategy)
                        )
                    }
                }

                Section("Companions") {
                    ForEach(MascotID.allCases, id: \.self) { mascot in
                        Toggle(
                            mascot.rawValue.capitalized,
                            isOn: mascotBinding(mascot)
                        )
                    }
                }

                Section {
                    Text(
                        "Keep at least one style and companion enabled. Jomado occasionally explores among your enabled choices so it can learn locally without uploading behavior data."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Your vibe")
            .onAppear(perform: load)
            .onChange(of: disabledStrategies) { _, _ in
                save()
            }
            .onChange(of: disabledMascots) { _, _ in
                save()
            }
        }
    }

    private func binding(_ strategy: Strategy) -> Binding<Bool> {
        Binding(
            get: {
                !disabledStrategies.contains(strategy)
            },
            set: { isEnabled in
                if isEnabled {
                    disabledStrategies.remove(strategy)
                } else if disabledStrategies.count < Strategy.allCases.count - 1 {
                    disabledStrategies.insert(strategy)
                }
            }
        )
    }

    private func mascotBinding(_ mascot: MascotID) -> Binding<Bool> {
        Binding(
            get: {
                !disabledMascots.contains(mascot)
            },
            set: { isEnabled in
                if isEnabled {
                    disabledMascots.remove(mascot)
                } else if disabledMascots.count < MascotID.allCases.count - 1 {
                    disabledMascots.insert(mascot)
                }
            }
        )
    }

    private func load() {
        let strategyValues =
            UserDefaults.standard.string(forKey: "disabledStrategies") ?? ""

        disabledStrategies = Set(
            strategyValues
                .split(separator: ",")
                .compactMap {
                    Strategy(rawValue: String($0))
                }
        )

        let mascotValues =
            UserDefaults.standard.string(forKey: "disabledMascots") ?? ""

        disabledMascots = Set(
            mascotValues
                .split(separator: ",")
                .compactMap {
                    MascotID(rawValue: String($0))
                }
        )
    }

    private func save() {
        UserDefaults.standard.set(
            disabledStrategies
                .map(\.rawValue)
                .joined(separator: ","),
            forKey: "disabledStrategies"
        )

        UserDefaults.standard.set(
            disabledMascots
                .map(\.rawValue)
                .joined(separator: ","),
            forKey: "disabledMascots"
        )
    }
}

private extension String {
    var displayName: String {
        replacingOccurrences(
            of: "RPG",
            with: " RPG"
        )
        .replacingOccurrences(
            of: "([a-z])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        .capitalized
    }
}
