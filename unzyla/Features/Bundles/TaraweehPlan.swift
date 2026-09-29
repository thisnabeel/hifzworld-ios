import Foundation
import Observation

struct TaraweehPlan: Codable, Equatable {
    var finishNight: Int
    var mushafID: Int

    static let minFinishNight = 8
    static let maxFinishNight = 30
    static let defaultFinishNight = 20

    static func clampedFinishNight(_ value: Int) -> Int {
        min(maxFinishNight, max(minFinishNight, value))
    }

    static func makeDefault(mushafID: Int) -> TaraweehPlan {
        TaraweehPlan(finishNight: defaultFinishNight, mushafID: mushafID)
    }
}

@MainActor
@Observable
final class TaraweehPlanStore {
    static let shared = TaraweehPlanStore()

    private let defaults = UserDefaults.standard
    private let key = "taraweehPlan"

    private(set) var plan: TaraweehPlan

    private init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(TaraweehPlan.self, from: data) {
            plan = TaraweehPlan(
                finishNight: TaraweehPlan.clampedFinishNight(decoded.finishNight),
                mushafID: decoded.mushafID
            )
        } else {
            plan = .makeDefault(mushafID: PreferencesStore.shared.mushafID)
        }
    }

    func updateFinishNight(_ night: Int) {
        plan.finishNight = TaraweehPlan.clampedFinishNight(night)
        persist()
    }

    func syncMushafID(_ mushafID: Int) {
        guard plan.mushafID != mushafID else { return }
        plan.mushafID = mushafID
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        defaults.set(data, forKey: key)
    }
}
