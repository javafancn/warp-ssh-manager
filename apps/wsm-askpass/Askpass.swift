import Foundation
import AppKit
import Security
import Darwin

// A dedicated, short-lived OpenSSH ASKPASS process. It never wraps an ssh
// command and never runs remotely. It writes ONLY the requested answer to stdout.
private struct Session: Decodable {
    let host_id: String
    let created_at: Int64
}
private let service = "dev.warpsshmanager.app.credentials.v1"

private func isPasswordPrompt(_ prompt: String) -> Bool {
    let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    // Don't hand a stored secret to a host-key confirmation, OTP, key-passphrase,
    // PAM challenge, or an arbitrary server-supplied questionnaire.
    return p == "password:" || p.hasSuffix("'s password:")
}

private func isInvokedBySystemSSH() -> Bool {
    // Defense in depth against directly launching this Keychain-reading helper.
    // The one-use token is not a complete isolation boundary for same-user code.
    var path=[CChar](repeating:0,count:4096)
    let size=proc_pidpath(getppid(),&path,UInt32(path.count))
    guard size > 0 else { return false }
    return String(cString:path) == "/usr/bin/ssh"
}

private func loadOnce() -> String? {
    guard isInvokedBySystemSSH() else { return nil }
    let env = ProcessInfo.processInfo.environment
    guard let token = env["WSM_ASKPASS_SESSION"],
          token.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil,
          let directory = env["WSM_ASKPASS_DIR"], directory.hasPrefix("/") else { return nil }
    let url=URL(fileURLWithPath:directory,isDirectory:true)
        .appendingPathComponent(token + ".json",isDirectory:false)
    var sb=stat()
    guard lstat(url.path,&sb) == 0,
          (sb.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
          sb.st_uid == getuid(), (sb.st_mode & 0o077) == 0 else { return nil }
    guard let data=try? Data(contentsOf:url),
          let session=try? JSONDecoder().decode(Session.self,from:data),
          UUID(uuidString:session.host_id) != nil,
          abs(Int64(Date().timeIntervalSince1970) - session.created_at) <= 120
    else { return nil }
    // Consume the authorization before accessing Keychain. Multiple password
    // challenges must never silently reuse the same stored secret.
    guard unlink(url.path) == 0 else { return nil }
    let query:[String:Any] = [
        kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:service,
        kSecAttrAccount as String:"\(session.host_id):ssh",
        kSecReturnData as String:true,
        kSecMatchLimit as String:kSecMatchLimitOne
    ]
    var result:CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary,&result) == errSecSuccess,
          let secret=result as? Data,
          let password=String(data:secret,encoding:.utf8), !password.isEmpty else { return nil }
    return password
}

private func askUser(_ prompt: String, secret: Bool) -> String? {
    let app=NSApplication.shared
    app.setActivationPolicy(.accessory)
    let alert=NSAlert()
    alert.messageText=secret ? "SSH 密码认证" : "SSH 交互认证"
    alert.informativeText=prompt
    alert.addButton(withTitle:"继续")
    alert.addButton(withTitle:"取消")
    let input:NSTextField = secret ? NSSecureTextField(frame:NSRect(x:0,y:0,width:330,height:24))
                                   : NSTextField(frame:NSRect(x:0,y:0,width:330,height:24))
    alert.accessoryView=input
    app.activate(ignoringOtherApps:true)
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    return input.stringValue
}

// Noninteractive smoke check runs on CI without opening any prompt or Keychain item.
if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--self-test" {
    let valid=["Password:","deploy@example.com's password:"]
    let invalid=["Enter OTP:","Enter passphrase for key:","Are you sure you want to continue connecting (yes/no)?"]
    exit(valid.allSatisfy(isPasswordPrompt) && invalid.allSatisfy { !isPasswordPrompt($0) }
        ? EXIT_SUCCESS : EXIT_FAILURE)
}
let prompt=CommandLine.arguments.dropFirst().joined(separator:" ")
if isPasswordPrompt(prompt), let saved=loadOnce() {
    print(saved)
    exit(EXIT_SUCCESS)
}
if let entered=askUser(prompt,secret:isPasswordPrompt(prompt)) {
    print(entered)
    exit(EXIT_SUCCESS)
}
exit(EXIT_FAILURE)
