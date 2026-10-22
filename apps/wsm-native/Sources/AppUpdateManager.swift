import SwiftUI
import AppKit

/// Checks the official stable GitHub Release without downloading or installing
/// anything until the user explicitly asks to open the installer link.
final class AppUpdateManager: ObservableObject {
    enum CheckState {
        case idle, checking, upToDate, available, failed
    }

    @Published private(set) var state: CheckState = .idle
    @Published private(set) var update: AvailableAppUpdate?
    @Published var showUpdateAlert = false

    let installedVersion: String =
        Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.0.0"

    private var hasCheckedAtLaunch = false

    static var currentArchitecture: String {
        #if arch(arm64)
        return "apple-silicon"
        #elseif arch(x86_64)
        return "intel"
        #else
        return "unknown"
        #endif
    }

    func checkAtLaunch() {
        guard !hasCheckedAtLaunch else { return }
        hasCheckedAtLaunch = true
        if UserDefaults.standard.object(forKey:"warp.updates.autoCheck") as? Bool ?? true {
            checkForUpdates(automatic:true)
        }
    }

    func checkForUpdates(automatic: Bool = false) {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url:AppUpdateRelease.latestEndpoint)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("WarpSSHManager-AppUpdater",forHTTPHeaderField:"User-Agent")

        URLSession.shared.dataTask(with:request) { [weak self] data,response,error in
            guard let self = self else { return }
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data = data, data.count <= 512_000
            else {
                DispatchQueue.main.async { self.state = .failed }
                return
            }
            do {
                let available = try AppUpdateRelease.newerRelease(
                    from:data,installed:self.installedVersion,
                    architecture:Self.currentArchitecture)
                DispatchQueue.main.async {
                    self.update = available
                    self.state = available == nil ? .upToDate : .available
                    if automatic && available != nil {
                        self.showUpdateAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async { self.state = .failed }
            }
        }.resume()
    }

    func downloadUpdate() {
        guard let url = update?.installerURL else { openReleasePage(); return }
        NSWorkspace.shared.open(url)
    }

    func openReleasePage() {
        guard let url = update?.releaseURL else { return }
        NSWorkspace.shared.open(url)
    }
}
