import SwiftUI
import UIKit

/// The note editor: plain text that is drawn as it reads (`NoteMarkup`).
/// Headings in three sizes, bullets that nest with a hanging indent, bold,
/// italic, and links that open on a tap. A bar over the keyboard does the
/// things a phone keyboard has no key for: heading, bullet, in, out, link.
///
/// A `UITextView`, because SwiftUI's `TextEditor` draws one style only. The
/// text it holds is the note itself, never changed by the drawing.
struct MarkupEditor: UIViewRepresentable {
    @Binding var text: String
    /// True while the keyboard is up. Setting it raises or lowers the keyboard.
    @Binding var typing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        let coordinator = context.coordinator
        coordinator.view = view
        view.delegate = coordinator
        view.backgroundColor = .clear
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 32, right: 0)
        view.tintColor = UIColor(Ink.violet)
        view.text = text
        view.inputAccessoryView = coordinator.bar()
        coordinator.restyle()

        // A tap on a link opens it; anywhere else the text view does what it always does.
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = coordinator
        view.addGestureRecognizer(tap)
        for other in view.gestureRecognizers ?? [] where other !== tap && other is UITapGestureRecognizer {
            other.require(toFail: tap)
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if view.text != text {
            view.text = text
            coordinator.restyle()
        }
        if typing, !view.isFirstResponder {
            // Not on screen yet while the page slides in: try again once it has.
            if view.window != nil {
                view.becomeFirstResponder()
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    if coordinator.parent.typing, !view.isFirstResponder { view.becomeFirstResponder() }
                }
            }
        } else if !typing, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        static let linkKey = NSAttributedString.Key("paradox.note.link")
        /// How far one tab moves a bullet in.
        static let tab: CGFloat = 22

        var parent: MarkupEditor
        weak var view: UITextView?

        init(_ parent: MarkupEditor) { self.parent = parent }

        // MARK: Drawing

        /// Draws the whole note again from its text. Only attributes change, so the caret stays put.
        func restyle() {
            // Mid-composition (Japanese, accents) the keyboard owns the text: leave it be.
            guard let view, view.markedTextRange == nil else { return }
            let storage = view.textStorage
            let text = storage.string
            let ns = text as NSString
            let full = NSRange(location: 0, length: storage.length)
            let size = UIFont.preferredFont(forTextStyle: .body).pointSize
            let body = Face.ui(size)
            let ink = UIColor(Ink.body), head = UIColor(Ink.head), muted = UIColor(Ink.muted), faint = UIColor(Ink.idle)

            let plain = NSMutableParagraphStyle()
            plain.lineSpacing = 3
            let base: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: ink, .paragraphStyle: plain]

            storage.beginEditing()
            storage.setAttributes(base, range: full)

            for line in NoteMarkup.lines(text) {
                switch line.kind {
                case .plain:
                    break
                case .heading(let level):
                    let sizes: [CGFloat] = [size + 11, size + 6, size + 2]
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineSpacing = 2
                    paragraph.paragraphSpacingBefore = line.range.location == 0 ? 0 : 8
                    paragraph.paragraphSpacing = 3
                    storage.addAttributes([.font: Face.ui(sizes[level - 1], level == 1 ? .bold : .semibold),
                                           .foregroundColor: head, .paragraphStyle: paragraph], range: line.range)
                    storage.addAttribute(.foregroundColor, value: faint, range: line.marker)
                case .bullet:
                    // Wrapped lines sit under the words, not under the bullet.
                    let prefix = ns.substring(with: line.marker)
                    let tabs = CGFloat(prefix.filter { $0 == "\t" }.count)
                    let rest = prefix.replacingOccurrences(of: "\t", with: "") as NSString
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineSpacing = 3
                    paragraph.tabStops = []
                    paragraph.defaultTabInterval = Self.tab
                    paragraph.headIndent = tabs * Self.tab + rest.size(withAttributes: [.font: body]).width
                    paragraph.paragraphSpacing = 2
                    storage.addAttribute(.paragraphStyle, value: paragraph, range: line.range)
                    storage.addAttribute(.foregroundColor, value: muted, range: line.marker)
                }
            }

            for stress in NoteMarkup.stresses(text) where NSMaxRange(stress.range) <= storage.length {
                let font = (storage.attribute(.font, at: stress.range.location, effectiveRange: nil) as? UIFont) ?? body
                let trait: UIFontDescriptor.SymbolicTraits = stress.bold ? .traitBold : .traitItalic
                if let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)) {
                    storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: stress.range)
                }
                if stress.bold { storage.addAttribute(.foregroundColor, value: head, range: stress.range) }
                for mark in stress.marks { storage.addAttribute(.foregroundColor, value: faint, range: mark) }
            }

            let accent = UIColor(Ink.violet)
            for link in NoteMarkup.links(text) where NSMaxRange(link.range) <= storage.length {
                storage.addAttributes([Self.linkKey: link.url, .foregroundColor: accent,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .underlineColor: accent.withAlphaComponent(0.5)], range: link.range)
                for part in link.faint { storage.addAttribute(.foregroundColor, value: faint, range: part) }
            }
            storage.endEditing()
            // What is typed next starts plain; the next pass gives it its line's style.
            view.typingAttributes = base
        }

        // MARK: Typing

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            restyle()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.typing { parent.typing = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.typing { parent.typing = false }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText string: String) -> Bool {
            let edit: NoteMarkup.Edit?
            switch string {
            case "\n": edit = NoteMarkup.afterReturn(textView.text, selection: range)
            case " " where range.length == 0: edit = NoteMarkup.afterSpace(textView.text, caret: range.location)
            default: edit = nil
            }
            guard let edit else { return true }
            apply(edit)
            return false
        }

        /// Makes one change through the text view, so Undo takes it back.
        func apply(_ edit: NoteMarkup.Edit?) {
            guard let edit, let view,
                  let start = view.position(from: view.beginningOfDocument, offset: edit.range.location),
                  let end = view.position(from: start, offset: edit.range.length),
                  let range = view.textRange(from: start, to: end) else { return }
            view.replace(range, withText: edit.replacement)
            view.selectedRange = NSRange(location: min(edit.caret, (view.text as NSString).length), length: 0)
            parent.text = view.text
            restyle()
        }

        // MARK: The bar over the keyboard

        func bar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            bar.tintColor = UIColor(Ink.head)
            func button(_ symbol: String, _ name: String, _ action: @escaping (Coordinator, UITextView) -> Void) -> UIBarButtonItem {
                let item = UIBarButtonItem(image: UIImage(systemName: symbol), primaryAction: UIAction { [weak self] _ in
                    guard let self, let view = self.view else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    action(self, view)
                })
                item.accessibilityLabel = name
                return item
            }
            let gap = UIBarButtonItem.fixedSpace(14)
            bar.items = [
                button("textformat.size", "Heading") { me, view in me.apply(NoteMarkup.cycleHeading(view.text, selection: view.selectedRange)) },
                gap,
                button("list.bullet", "Bullet") { me, view in me.apply(NoteMarkup.toggleBullet(view.text, selection: view.selectedRange)) },
                gap,
                button("decrease.indent", "Move out") { me, view in me.apply(NoteMarkup.shift(view.text, selection: view.selectedRange, by: -1)) },
                gap,
                button("increase.indent", "Move in") { me, view in me.apply(NoteMarkup.shift(view.text, selection: view.selectedRange, by: 1)) },
                gap,
                button("link", "Link") { me, view in me.apply(NoteMarkup.link(view.text, selection: view.selectedRange)) },
                .flexibleSpace(),
                button("keyboard.chevron.compact.down", "Hide keyboard") { _, view in view.resignFirstResponder() },
            ]
            bar.sizeToFit()
            return bar
        }

        // MARK: Links

        /// The link under a point, if the point is on its words.
        func link(at point: CGPoint) -> URL? {
            guard let view, let position = view.closestPosition(to: point) else { return nil }
            let index = view.offset(from: view.beginningOfDocument, to: position)
            let storage = view.textStorage
            for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
                var range = NSRange()
                guard let url = storage.attribute(Self.linkKey, at: candidate, effectiveRange: &range) as? URL,
                      let start = view.position(from: view.beginningOfDocument, offset: range.location),
                      let end = view.position(from: start, offset: range.length),
                      let words = view.textRange(from: start, to: end) else { continue }
                if view.selectionRects(for: words).contains(where: { $0.rect.insetBy(dx: -6, dy: -6).contains(point) }) {
                    return url
                }
            }
            return nil
        }

        @objc func tapped(_ tap: UITapGestureRecognizer) {
            guard let view, let url = link(at: tap.location(in: view)) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view else { return false }
            return link(at: touch.location(in: view)) != nil
        }
    }
}
