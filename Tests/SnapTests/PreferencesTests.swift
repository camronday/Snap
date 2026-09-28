import Testing
@testable import Snap

struct PreferencesTests {
    @Test func defaultsMatchPlan() {
        #expect(PreferencesDefault.annotationColour == "FF0000FF")
        #expect(PreferencesDefault.retinaClipboard == true)
        #expect(PreferencesDefault.gifMaxDuration == 30)
        #expect(PreferencesRange.gifMaxDuration == 5...120)
    }
}
