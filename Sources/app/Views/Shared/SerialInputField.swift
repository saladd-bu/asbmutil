import SwiftUI

/// A multi-line, scrollable serial-number entry field shared by Device Lookup and
/// Assignments. Backed by `TextEditor` so a large pasted list scrolls **inside** the
/// field once it hits `maxHeight`, rather than growing without bound or clipping — the
/// behavior `TextField(axis: .vertical)` can't provide. Accepts commas, spaces, or new
/// lines; the caller does the parsing (see `CSVParser.parseSerialTokens`).
///
/// The accepted-separators hint sits as a caption *below* the field rather than as an
/// in-field placeholder — a `TextEditor`'s text inset doesn't line up with an overlaid
/// placeholder, so the caret and prompt appear misaligned.
///
/// Submit is left to the caller's primary button via ⌘↩ (a `TextEditor` treats plain
/// Return as a newline), so this view carries no submit action.
struct SerialInputField: View {
    @Binding var text: String
    var isDisabled: Bool = false
    @FocusState.Binding var isFocused: Bool
    var minHeight: CGFloat = 80
    var maxHeight: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(Spacing.xs)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .focused($isFocused)
                .disabled(isDisabled)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(isDisabled ? 0.4 : 1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6).strokeBorder(.separator)
                )

            Text("Separate serials with commas, spaces, or new lines.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
