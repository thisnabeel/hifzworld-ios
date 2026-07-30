import Foundation

struct MinVersionCheckResult {
    let blocked: Bool
    let minVersion: String?
    let installed: String?
    let appStoreId: String?
}

enum GlobalConfigService {
    private static let hifzworldBundleID = "com.nabeel.hifzworld"

    static func installedVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    @MainActor
    static func checkMinVersion(client: HifzworldAPIClient = .shared) async -> MinVersionCheckResult {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let installed = installedVersion()
        guard bundleID == hifzworldBundleID else {
            return MinVersionCheckResult(blocked: false, minVersion: nil, installed: installed, appStoreId: nil)
        }

        do {
            let config: HifzworldAppConfig = try await client.get("/api/app_config", authorized: false)
            let storeId = config.appStoreId?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let min = config.minAppVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !min.isEmpty
            else {
                return MinVersionCheckResult(
                    blocked: false,
                    minVersion: nil,
                    installed: installed,
                    appStoreId: storeId.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
            let blocked = Semver.isLessThan(installed, min)
            return MinVersionCheckResult(
                blocked: blocked,
                minVersion: min,
                installed: installed,
                appStoreId: storeId.flatMap { $0.isEmpty ? nil : $0 }
            )
        } catch {
            // Fail open: don't brick the app offline or on API errors.
            return MinVersionCheckResult(blocked: false, minVersion: nil, installed: installed, appStoreId: nil)
        }
    }
}
