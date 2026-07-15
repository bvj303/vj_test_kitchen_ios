import Testing
@testable import VJTestKitchen

/// The fixed-perch anchor's core rule: an incoming tip must never open the
/// bubble itself (that was the old cameo's intrusion) — it only flags an unread
/// tip the user chooses to read. `autoCollapseDelay: nil` keeps these synchronous.
@MainActor
struct SpatchPerchViewModelTests {
    private func makeVM() -> SpatchPerchViewModel {
        SpatchPerchViewModel(initialMessage: "hi", initialMood: .idle, autoCollapseDelay: nil)
    }

    @Test func postWhileCollapsedFlagsUnreadWithoutOpening() {
        let vm = makeVM()
        vm.post("Try the carbonara", mood: .happy)

        #expect(vm.message == "Try the carbonara")
        #expect(vm.mood == .happy)
        #expect(vm.isExpanded == false)      // never forced open
        #expect(vm.hasUnreadTip == true)
    }

    @Test func postBumpsAttentionNonce() {
        let vm = makeVM()
        let before = vm.attentionNonce
        vm.post("one")
        vm.post("two")
        #expect(vm.attentionNonce == before + 2)
    }

    @Test func expandClearsUnread() {
        let vm = makeVM()
        vm.post("A tip")
        #expect(vm.hasUnreadTip == true)

        vm.expand()
        #expect(vm.isExpanded == true)
        #expect(vm.hasUnreadTip == false)
    }

    @Test func toggleOpensThenCloses() {
        let vm = makeVM()
        #expect(vm.isExpanded == false)
        vm.toggle()
        #expect(vm.isExpanded == true)
        vm.toggle()
        #expect(vm.isExpanded == false)
    }

    @Test func postWhileExpandedReplacesLineAndStaysOpenWithoutUnread() {
        let vm = makeVM()
        vm.expand()
        vm.post("Fresh line", mood: .laughing)

        #expect(vm.message == "Fresh line")
        #expect(vm.mood == .laughing)
        #expect(vm.isExpanded == true)       // stays open — user is reading
        #expect(vm.hasUnreadTip == false)    // nothing unread while open
    }

    @Test func cycleSwapsLineButKeepsBubbleOpen() {
        let vm = makeVM()
        vm.expand()
        vm.cycle(to: "Another one", mood: .surprised)

        #expect(vm.message == "Another one")
        #expect(vm.mood == .surprised)
        #expect(vm.isExpanded == true)
    }
}
