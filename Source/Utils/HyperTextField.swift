//
//  HyperTextField.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import Cocoa

@IBDesignable
class HyperTextField: NSTextField {
    @IBInspectable var href: String = ""

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(self.bounds, cursor: NSCursor.pointingHand)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.blue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        self.attributedStringValue = NSAttributedString(string: self.stringValue, attributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        if let localHref = URL(string: href) {
            NSWorkspace.shared.open(localHref)
        }
    }
}
