import CoreGraphics
import Testing
@testable import Snap

struct WindowPickerTests {
    @Test func convertsGlobalFrameToDisplayLocalPoints() {
        // A secondary display positioned to the right of the primary one.
        let displayBounds = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let windowGlobalFrame = CGRect(x: 2020, y: 100, width: 400, height: 300)

        let local = WindowPicker.localFrame(for: windowGlobalFrame, displayBounds: displayBounds)

        #expect(local == CGRect(x: 100, y: 100, width: 400, height: 300))
    }

    @Test func primaryDisplayLeavesFrameUnchanged() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowGlobalFrame = CGRect(x: 50, y: 60, width: 200, height: 150)

        let local = WindowPicker.localFrame(for: windowGlobalFrame, displayBounds: displayBounds)

        #expect(local == windowGlobalFrame)
    }
}
