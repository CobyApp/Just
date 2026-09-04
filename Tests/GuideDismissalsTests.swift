import Foundation
import JustDesign
import Testing

@Suite("안내 닫기 기억")
@MainActor
struct GuideDismissalsTests {
    private func fresh() -> (GuideDismissals, UserDefaults) {
        let name = "guides-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (GuideDismissals(defaults: defaults), defaults)
    }

    @Test("닫은 안내는 다음 실행에서도 닫혀 있다")
    func persists() {
        let (store, defaults) = fresh()
        store.dismiss("home.start")
        #expect(store.isDismissed("home.start"))
        #expect(!store.isDismissed("library.howto"))

        let again = GuideDismissals(defaults: defaults)
        #expect(again.isDismissed("home.start"))
    }

    @Test("다시 보기는 전부 되살린다")
    func restore() {
        let (store, defaults) = fresh()
        store.dismiss("a"); store.dismiss("b")
        store.restoreAll()
        #expect(store.dismissed.isEmpty)
        #expect(GuideDismissals(defaults: defaults).dismissed.isEmpty)
    }
}
