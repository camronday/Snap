import SwiftUI

/// A borderless inline text field for the text tool, styled like a caret at
/// the click point. Commits on Return or losing focus, discards if empty.
/// Shared by the overlay's `SelectionView` and the editor's `EditorCanvasView`.
struct TextEntryField: View {
    let origin: CGPoint
    let colour: RGBAColour
    let onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: Annotation.textFontSize, weight: .semibold))
            .foregroundStyle(colour.color)
            .fixedSize()
            .focused($focused)
            .onSubmit { onCommit(text) }
            .position(x: origin.x + 60, y: origin.y)
            .onAppear { focused = true }
    }
}
