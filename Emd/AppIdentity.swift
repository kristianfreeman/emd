import Foundation

/// Which copy of Emd this is. The Debug build has its own bundle ID, so it keeps its own settings, Keychain
/// items, saved text, and logs, and can run beside the installed app without touching the post being written
/// there.
enum AppIdentity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.kristianfreeman.emd"
    static let isDebugCopy = bundleID.hasSuffix(".debug")
    /// The folder under Application Support and Logs: `Emd`, or `Emd Debug` for the Debug build.
    static let folder = isDebugCopy ? "Emd Debug" : "Emd"
    /// The app is only hosting unit tests. It opens no post and never connects to the site.
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
