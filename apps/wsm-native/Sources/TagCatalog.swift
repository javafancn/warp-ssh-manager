import Foundation

/// All persisted host tags are reusable. No separate tag database is needed:
/// existing records automatically populate this catalog after each snapshot.
enum HostTagCatalog {
    static func key(_ value:String) -> String {
        value.trimmingCharacters(in:.whitespacesAndNewlines)
            .folding(options:[.caseInsensitive,.diacriticInsensitive],
                     locale:Locale(identifier:"en_US_POSIX"))
    }

    static func available(_ savedTags:[String],excluding assigned:[String] = [],
                          search query:String = "") -> [String] {
        let excluded=Set(assigned.map(key))
        let searchKey=key(query)
        var seen:Set<String>=[]
        return savedTags.compactMap { original -> String? in
            let candidate=original.trimmingCharacters(in:.whitespacesAndNewlines)
            let id=key(candidate)
            guard !id.isEmpty,!excluded.contains(id),seen.insert(id).inserted,
                  searchKey.isEmpty || id.contains(searchKey) else {return nil}
            return candidate
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Typing an existing tag with different casing reuses its stored spelling
    /// (and thus its deterministic badge appearance) rather than creating a variant.
    static func canonical(_ typed:String,in available:[String]) -> String {
        let candidate=typed.trimmingCharacters(in:.whitespacesAndNewlines)
        return available.first(where:{key($0)==key(candidate)}) ?? candidate
    }
}
