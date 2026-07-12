import Foundation

struct MinVersionCheckResult {
    let blocked: Bool
    let minVersion: String?
    let installed: String?
}

enum GlobalConfigService {
    private static let aswaatBundleID = "com.aswaat.app"

    static func installedVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func checkMinVersion(client: APIClient = .shared) async -> MinVersionCheckResult {
        // min_ios_version applies to the production Aswaat app, not the separate unzyla build.
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard bundleID == aswaatBundleID else {
            return MinVersionCheckResult(blocked: false, minVersion: nil, installed: installedVersion())
        }

        do {
            let config = try await client.fetchGlobalConfig()
            guard let min = config.minIosVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !min.isEmpty
            else {
                return MinVersionCheckResult(blocked: false, minVersion: nil, installed: installedVersion())
            }
            let installed = installedVersion()
            let blocked = Semver.isLessThan(installed, min)
            return MinVersionCheckResult(blocked: blocked, minVersion: min, installed: installed)
        } catch {
            return MinVersionCheckResult(blocked: false, minVersion: nil, installed: installedVersion())
        }
    }
}
