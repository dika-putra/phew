import Foundation
import PhewCore

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func stateText(_ state: ItemState) -> String {
    switch state {
    case .ready: ""
    case .inUse(let app): "in use: \(app)"
    case .unreadable: "can't read"
    }
}

func status(_ message: String) {
    if isatty(2) == 1 { FileHandle.standardError.write(Data("\(message)\n".utf8)) }
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
}

func loadTargets() -> [PathTarget] {
    let loaded = ConfigStore().load()
    loaded.issues.forEach { warn($0.message) }
    return Catalog.all(custom: loaded.validTargets)
}
