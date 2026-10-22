import Foundation

@main
enum AppUpdateSmoke {
    static func payload(tag: String = "v1.0.4",
                        releaseHost: String = "github.com",
                        assetHost: String = "github.com",
                        draft: Bool = false,
                        prerelease: Bool = false) throws -> Data {
        let filename = "WarpSSHManager-1.0.4-apple-silicon.dmg"
        let base = "/javafancn/warp-ssh-manager/releases/"
        let release: [String:Any] = [
            "tag_name":tag,
            "html_url":"https://" + releaseHost + base + "tag/" + tag,
            "draft":draft,
            "prerelease":prerelease,
            "assets":[[
                "name":filename,
                "browser_download_url":"https://" + assetHost + base +
                                        "download/" + tag + "/" + filename
            ]]
        ]
        return try JSONSerialization.data(withJSONObject:release)
    }

    static func main() throws {
        assert(UpdateVersion("1.0.3") == UpdateVersion("v1.0.3"))
        assert(UpdateVersion("1.0.10")! > UpdateVersion("1.0.9")!)
        assert(UpdateVersion("2.0.0")! > UpdateVersion("1.99.99")!)
        assert(UpdateVersion("1.0") == nil)
        assert(UpdateVersion("1.0.4-beta") == nil)
        assert(UpdateVersion("1.0.x") == nil)

        let body = try payload()
        let arm = try AppUpdateRelease.newerRelease(
            from:body,installed:"1.0.3",architecture:"apple-silicon")
        assert(arm?.version == "1.0.4")
        assert(arm?.installerURL?.lastPathComponent == "WarpSSHManager-1.0.4-apple-silicon.dmg")
        let upToDate = try AppUpdateRelease.newerRelease(
            from:body,installed:"1.0.4",architecture:"apple-silicon")
        let newerInstalled = try AppUpdateRelease.newerRelease(
            from:body,installed:"1.2.0",architecture:"apple-silicon")
        assert(upToDate == nil)
        assert(newerInstalled == nil)

        // An architecture without an official matching DMG still opens the
        // release notes, never the wrong machine's binary.
        let intel = try AppUpdateRelease.newerRelease(
            from:body,installed:"1.0.3",architecture:"intel")
        assert(intel?.installerURL == nil)
        assert(intel?.releaseURL.host == "github.com")

        // Reject an untrusted release page entirely. A misleading third-party
        // installer asset must not be selected even if its name looks correct.
        assert((try? AppUpdateRelease.newerRelease(
            from:payload(releaseHost:"example.com"),installed:"1.0.3",
            architecture:"apple-silicon")) == nil)
        let unsafeInstaller = try AppUpdateRelease.newerRelease(
            from:payload(assetHost:"example.com"),installed:"1.0.3",
            architecture:"apple-silicon")
        assert(unsafeInstaller?.installerURL == nil)
        assert((try? AppUpdateRelease.newerRelease(
            from:payload(draft:true),installed:"1.0.3",
            architecture:"apple-silicon")) == nil)
        assert((try? AppUpdateRelease.newerRelease(
            from:payload(prerelease:true),installed:"1.0.3",
            architecture:"apple-silicon")) == nil)
        print("PASS: semantic versions, stable release check, architecture-safe installers, trusted URLs")
    }
}
