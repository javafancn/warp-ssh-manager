import Foundation

@main
struct TagCatalogSmoke {
    static func main() {
        let saved=["production","test","Dev","Production","  测试环境  ","TEST","",
                   "staging","équipe"]
        assert(HostTagCatalog.available(saved)==["Dev","équipe","production","staging","test","测试环境"].sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        })
        assert(HostTagCatalog.available(saved,excluding:["PRODUCTION","dev"])
               == ["équipe","staging","test","测试环境"].sorted {
                    $0.localizedStandardCompare($1) == .orderedAscending
               })
        assert(HostTagCatalog.available(saved,search:"PROD")==["production"])
        assert(HostTagCatalog.available(saved,search:"测试")==["测试环境"])
        assert(HostTagCatalog.canonical("ProDuCtIoN",in:saved)=="production")
        assert(HostTagCatalog.canonical(" new-tag ",in:saved)=="new-tag")
        assert(HostTagCatalog.available([],excluding:[]).isEmpty)
        print("PASS: reusable host-tag catalog, casefold, filtering, canonical labels")
    }
}
