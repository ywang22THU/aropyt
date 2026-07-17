import AppKit
import MarkdownCore

/// 源码模式：NSTextView + 简单正则语法高亮。
final class SourceViewController: NSViewController, NSTextViewDelegate {

    /// 不要用 lazy var：在 loadView 中通过 helper 创建 NSTextView 后，
    /// 容易出现 scrollView 持有的实例和 self 属性不是同一个的诡异情况。
    /// 改用普通可选属性，loadView 中显式赋值。
    private var textView: NSTextView?
    private var scrollView: NSScrollView?
    private let highlighter = MarkdownHighlighter()
    private let highlightBatchSize = 64 * 1024
    private var highlightGeneration = 0
    private var backgroundHighlightOffset: Int?
    private var pendingEditedRange: NSRange?
    private var pendingReplacementLength = 0
    private var pendingUTF8ByteDelta = 0
    private var pendingLineBreakDelta = 0
    private var isApplyingHighlight = false
    private var currentUTF8ByteCount = 0
    private var currentLineBreakCount = 0
    private var usesProgressiveHighlighting = false

    /// 文本变化回调（用户编辑触发）
    var onTextChanged: ((String) -> Void)?

    var currentText: String {
        return textView?.string ?? ""
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.translatesAutoresizingMaskIntoConstraints = true

        let contentSize = scroll.contentSize
        let tv = NSTextView(frame: NSRect(x: 0, y: 0,
                                          width: contentSize.width,
                                          height: contentSize.height))
        // NSTextView 必备配置 —— 不设这几项可能整片空白
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.layoutManager?.allowsNonContiguousLayout = true

        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.usesFontPanel = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.textColor = NSColor.textColor
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.insertionPointColor = NSColor.textColor
        tv.delegate = self

        scroll.documentView = tv

        self.textView = tv
        self.scrollView = scroll
        self.view = scroll
    }

    /// 由外部（document 加载完成、模式切换）调用，强制设置内容并触发高亮。
    func setText(_ s: String) {
        _ = self.view
        guard let tv = textView else { return }
        if tv.string != s {
            tv.string = s
        }
        startInitialHighlighting(for: s)
    }

    /// Returns the UTF-16 source offset currently aligned with the top of the
    /// visible source viewport. NSTextView and JavaScript strings both use this
    /// coordinate system, so no lossy Unicode conversion is needed.
    func viewportSourceOffset() -> Int {
        guard
            let textView,
            let scrollView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer,
            layoutManager.numberOfGlyphs > 0
        else { return 0 }

        let visibleRect = scrollView.contentView.bounds
        layoutManager.ensureLayout(forBoundingRect: visibleRect, in: textContainer)
        let origin = textView.textContainerOrigin
        let containerPoint = NSPoint(
            x: max(0, visibleRect.minX - origin.x),
            y: max(0, visibleRect.minY - origin.y)
        )
        let glyphIndex = min(
            layoutManager.glyphIndex(for: containerPoint, in: textContainer),
            max(0, layoutManager.numberOfGlyphs - 1)
        )
        return min(layoutManager.characterIndexForGlyph(at: glyphIndex), textView.textStorage?.length ?? 0)
    }

    /// Aligns a UTF-16 source offset with the top of the source viewport without
    /// changing the user's selection.
    func scrollToSourceOffset(_ requestedOffset: Int) {
        performScrollToSourceOffset(requestedOffset)
        // NSTextView may update its document height after the current run-loop
        // turn when it has just been embedded or received new text. Reapply once
        // after layout settles so the clip view does not clamp to the old height.
        DispatchQueue.main.async { [weak self] in
            self?.performScrollToSourceOffset(requestedOffset)
        }
    }

    private func performScrollToSourceOffset(_ requestedOffset: Int) {
        guard
            let textView,
            let scrollView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer,
            let storage = textView.textStorage,
            storage.length > 0
        else { return }

        let offset = min(max(0, requestedOffset), storage.length - 1)
        let characterRange = NSRange(location: offset, length: 1)
        layoutManager.ensureGlyphs(forCharacterRange: characterRange)
        layoutManager.ensureLayout(forCharacterRange: characterRange)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let target = NSPoint(
            x: scrollView.contentView.bounds.minX,
            y: max(0, glyphRect.minY + textView.textContainerOrigin.y)
        )
        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func startInitialHighlighting(for text: String) {
        highlightGeneration &+= 1
        let generation = highlightGeneration
        guard let storage = textView?.textStorage else { return }
        currentUTF8ByteCount = text.utf8.count
        currentLineBreakCount = Self.lineBreakCount(in: text)
        usesProgressiveHighlighting = LongDocumentPolicy.isLongDocument(
            utf8ByteCount: currentUTF8ByteCount,
            lineCount: text.isEmpty ? 0 : currentLineBreakCount + 1
        )
        resetBaseAttributes(in: NSRange(location: 0, length: storage.length))

        if !usesProgressiveHighlighting {
            backgroundHighlightOffset = nil
            applyHighlighting(in: NSRange(location: 0, length: storage.length))
            return
        }

        backgroundHighlightOffset = 0
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.highlightGeneration else { return }
            self.highlightVisibleRange()
            self.scheduleHighlightBatch(from: 0, generation: generation)
        }
    }

    private func applyHighlighting(in requestedRange: NSRange) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = MarkdownHighlighter.expandedHighlightRange(
            for: requestedRange,
            in: storage.string as NSString
        )
        guard range.length > 0 else { return }
        isApplyingHighlight = true
        storage.beginEditing()
        resetBaseAttributes(in: range)
        highlighter.apply(to: storage, range: range)
        storage.endEditing()
        isApplyingHighlight = false
    }

    private func resetBaseAttributes(in range: NSRange) {
        guard let storage = textView?.textStorage, range.length > 0 else { return }
        storage.removeAttribute(.foregroundColor, range: range)
        storage.removeAttribute(.font, range: range)
        storage.removeAttribute(.link, range: range)
        storage.addAttribute(
            .font,
            value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            range: range
        )
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
    }

    private func highlightVisibleRange() {
        guard
            let tv = textView,
            let scrollView,
            let layoutManager = tv.layoutManager,
            let textContainer = tv.textContainer
        else { return }

        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: scrollView.contentView.bounds,
            in: textContainer
        )
        var characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let lower = max(0, characterRange.location - 4_096)
        let upper = min(tv.textStorage?.length ?? 0, NSMaxRange(characterRange) + 4_096)
        characterRange = NSRange(location: lower, length: max(0, upper - lower))
        applyHighlighting(in: characterRange)
    }

    private func scheduleHighlightBatch(from offset: Int, generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard
                generation == self.highlightGeneration,
                let storage = self.textView?.textStorage,
                self.backgroundHighlightOffset == offset,
                offset < storage.length
            else {
                if generation == self.highlightGeneration,
                   offset >= (self.textView?.textStorage?.length ?? 0) {
                    self.backgroundHighlightOffset = nil
                }
                return
            }

            let length = min(self.highlightBatchSize, storage.length - offset)
            let requested = NSRange(location: offset, length: length)
            let expanded = MarkdownHighlighter.expandedHighlightRange(
                for: requested,
                in: storage.string as NSString
            )
            self.applyHighlighting(in: expanded)
            let nextOffset = max(offset + length, NSMaxRange(expanded))
            if nextOffset < storage.length {
                self.backgroundHighlightOffset = nextOffset
                self.scheduleHighlightBatch(from: nextOffset, generation: generation)
            } else {
                self.backgroundHighlightOffset = nil
            }
        }
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let tv = textView else { return }
        onTextChanged?(tv.string)
        highlightGeneration &+= 1
        let wasProgressive = usesProgressiveHighlighting
        let replacementLength = pendingReplacementLength
        let editedRange = pendingEditedRange ?? tv.selectedRange()
        let utf16Delta = replacementLength - editedRange.length
        pendingEditedRange = nil
        pendingReplacementLength = 0
        currentUTF8ByteCount = max(0, currentUTF8ByteCount + pendingUTF8ByteDelta)
        currentLineBreakCount = max(0, currentLineBreakCount + pendingLineBreakDelta)
        pendingUTF8ByteDelta = 0
        pendingLineBreakDelta = 0
        usesProgressiveHighlighting = LongDocumentPolicy.isLongDocument(
            utf8ByteCount: currentUTF8ByteCount,
            lineCount: tv.string.isEmpty ? 0 : currentLineBreakCount + 1
        )
        let storageLength = tv.textStorage?.length ?? 0
        let affected = NSRange(
            location: min(editedRange.location, storageLength),
            length: replacementLength
        )
        applyHighlighting(in: affected)

        if usesProgressiveHighlighting, let oldOffset = backgroundHighlightOffset {
            let adjustedOffset: Int
            if editedRange.location < oldOffset {
                adjustedOffset = max(0, oldOffset + utf16Delta)
            } else {
                adjustedOffset = oldOffset
            }
            backgroundHighlightOffset = min(adjustedOffset, storageLength)
            let generation = highlightGeneration
            scheduleHighlightBatch(from: backgroundHighlightOffset ?? 0, generation: generation)
        } else if wasProgressive && !usesProgressiveHighlighting && backgroundHighlightOffset != nil {
            backgroundHighlightOffset = nil
            applyHighlighting(in: NSRange(location: 0, length: storageLength))
        }
    }

    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        guard !isApplyingHighlight else { return true }
        pendingEditedRange = affectedCharRange
        let replacement = replacementString ?? ""
        pendingReplacementLength = (replacement as NSString).length
        let oldText = textView.string as NSString
        let removed = oldText.substring(with: affectedCharRange)
        pendingUTF8ByteDelta = replacement.utf8.count - removed.utf8.count
        let contextStart = max(0, affectedCharRange.location - 1)
        let contextEnd = min(oldText.length, NSMaxRange(affectedCharRange) + 1)
        let oldContextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
        let oldContext = oldText.substring(with: oldContextRange)
        let prefixRange = NSRange(
            location: contextStart,
            length: affectedCharRange.location - contextStart
        )
        let suffixRange = NSRange(
            location: NSMaxRange(affectedCharRange),
            length: contextEnd - NSMaxRange(affectedCharRange)
        )
        let newContext = oldText.substring(with: prefixRange)
            + replacement
            + oldText.substring(with: suffixRange)
        pendingLineBreakDelta = Self.lineBreakCount(in: newContext)
            - Self.lineBreakCount(in: oldContext)
        return true
    }

    private static func lineBreakCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        var previousWasCarriageReturn = false
        for byte in text.utf8 {
            if byte == 0x0D {
                count += 1
                previousWasCarriageReturn = true
            } else {
                if byte == 0x0A, !previousWasCarriageReturn { count += 1 }
                previousWasCarriageReturn = false
            }
        }
        return count
    }

    /// 只有 Cmd+Click 才打开链接，普通点击仅移动光标。
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard NSEvent.modifierFlags.contains(.command) else { return true }
        if let url = link as? URL {
            NSWorkspace.shared.open(url)
            return true
        }
        if let s = link as? String, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }
}
