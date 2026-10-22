import Foundation

// Keep release parsing and version selection independent of SwiftUI/AppKit,
// so the same checks can be tested without installing an application.
struct UpdateVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let cleaned = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isNumber && $0.isASCII }) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    var string: String { String(major) + "." + String(minor) + "." + String(patch) }
}

struct AvailableAppUpdate {
    let version: String
    let releaseURL: URL
    let installerURL: URL?
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }
}

enum UpdateReleaseError: Error {
    case invalidRelease
}

enum AppUpdateRelease {
    static let latestEndpoint = URL(string:
        "https://api.github.com/repos/javafancn/warp-ssh-manager/releases/latest")!

    // GitHub's 'latest' endpoint selects a stable release; reject draft and
    // prerelease flags again to guard against an unexpected API response.
    static func newerRelease(from data: Data, installed: String,
                             architecture: String) throws -> AvailableAppUpdate? {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let remoteVersion = UpdateVersion(release.tagName),
              !release.draft, !release.prerelease,
              release.htmlURL.scheme == "https",
              release.htmlURL.host == "github.com",
              release.htmlURL.path == "/javafancn/warp-ssh-manager/releases/tag/" + release.tagName
        else { throw UpdateReleaseError.invalidRelease }

        guard let currentVersion = UpdateVersion(installed) else {
            throw UpdateReleaseError.invalidRelease
        }
        guard remoteVersion > currentVersion else { return nil }

        let assetName = "WarpSSHManager-" + remoteVersion.string + "-" +
                        architecture + ".dmg"
        let downloadPath = "/javafancn/warp-ssh-manager/releases/download/" +
                           release.tagName + "/" + assetName
        let installer = release.assets.first(where: {
            $0.name == assetName &&
            $0.browserDownloadURL.scheme == "https" &&
            $0.browserDownloadURL.host == "github.com" &&
            $0.browserDownloadURL.path == downloadPath
        })?.browserDownloadURL

        return AvailableAppUpdate(version:remoteVersion.string,
                                  releaseURL:release.htmlURL,
                                  installerURL:installer)
    }
}
