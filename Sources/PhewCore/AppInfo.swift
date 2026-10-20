import Foundation

public enum AppInfo {
    public static let name = "Phew"
    public static let version = "0.1.0"
    public static let author = "Dika Putra"
    public static let repoURL = URL(string: "https://github.com/dika-putra/phew")!

    public static var versionLine: String { "phew \(version) (\(repoURL.absoluteString))" }
}
