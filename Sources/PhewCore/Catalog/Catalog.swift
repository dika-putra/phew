public enum Catalog {
    public static func all(custom: [CustomTargetSpec]) -> [PathTarget] {
        BuiltinCatalog.targets + custom.map {
            PathTarget(id: $0.id, group: "Extra folders", title: $0.title, tier: $0.tier, paths: $0.paths)
        }
    }
}
