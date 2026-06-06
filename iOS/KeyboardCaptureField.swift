import SwiftUI
import UIKit

/// Invisible field that captures the system keyboard's keystrokes and
/// forwards them character by character (including backspace and return).
struct KeyboardCaptureField: UIViewRepresentable {
    var onText: (String) -> Void
    var onBackspace: () -> Void
    var onReturn: () -> Void
    @Binding var isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CaptureTextField {
        let field = CaptureTextField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.inlinePredictionType = .no
        field.keyboardAppearance = .dark
        field.returnKeyType = .default
        field.tintColor = .clear
        field.textColor = .clear
        field.onBackspace = { onBackspace() }
        return field
    }

    func updateUIView(_ field: CaptureTextField, context: Context) {
        if isActive && !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isActive && field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: KeyboardCaptureField
        init(_ parent: KeyboardCaptureField) { self.parent = parent }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            if string == "\n" {
                parent.onReturn()
            } else if !string.isEmpty {
                parent.onText(string)
            }
            // Keep the field empty: we only use it as an event source.
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false
        }
    }
}

/// Subclass that detects backspace even when the field is empty.
final class CaptureTextField: UITextField {
    var onBackspace: (() -> Void)?
    override func deleteBackward() {
        onBackspace?()
        super.deleteBackward()
    }
}
