import Cocoa

/// Detects other FlowKeys builds running at the same time.
///
/// This exists because of a real failure: a year-old Xcode build sitting in
/// DerivedData under a different bundle identifier was launched from
/// Spotlight and ran alongside the installed app. macOS only prevents two
/// instances of the *same* bundle id, so it happily ran both — and the stale
/// one, which used a passive event monitor, made ⌘V look broken while the
/// real build sat idle.
///
/// Nothing in the UI made that diagnosable, so now it is.
enum InstanceCheck {

    struct Other {
        let name: String
        let path: String
        let bundleID: String?
    }

    /// Running applications that look like another FlowKeys build.
    static func otherRunningBuilds() -> [Other] {
        let me = Bundle.main.bundleIdentifier
        let myPath = Bundle.main.bundlePath

        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let url = app.bundleURL else { return nil }
            let path = url.path
            guard path != myPath else { return nil }
            guard url.lastPathComponent.localizedCaseInsensitiveContains("FlowKeys")
                    || (app.localizedName?.localizedCaseInsensitiveContains("FlowKeys") ?? false)
            else { return nil }
            // Same identifier at a different path is still a different build.
            if let me, app.bundleIdentifier == me, path == myPath { return nil }
            return Other(
                name: app.localizedName ?? url.lastPathComponent,
                path: path,
                bundleID: app.bundleIdentifier
            )
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Short, human-readable location for the menu, e.g. "/Applications".
    static var locationDescription: String {
        let path = Bundle.main.bundlePath
        if path.hasPrefix("/Applications") { return "/Applications" }
        if path.contains("DerivedData") { return "⚠︎ Xcode build folder" }
        if path.contains("/.build/") { return "⚠︎ build directory" }
        return (path as NSString).deletingLastPathComponent
    }
}
