import SwiftUI
import AppKit

struct ServerComboBox: NSViewRepresentable {
    @Binding var text: String
    var items: [String]
    var onSubmit: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.addItems(withObjectValues: items)
        comboBox.stringValue = text
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        comboBox.removeAllItems()
        comboBox.addItems(withObjectValues: items)
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSComboBoxDelegate, NSTextFieldDelegate {
        let parent: ServerComboBox

        init(_ parent: ServerComboBox) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let comboBox = obj.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            DispatchQueue.main.async {
                if comboBox.indexOfSelectedItem >= 0 {
                    self.parent.text = comboBox.itemObjectValue(at: comboBox.indexOfSelectedItem) as? String ?? ""
                }
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.text = control.stringValue
                parent.onSubmit?()
                return true
            }
            return false
        }
    }
}
