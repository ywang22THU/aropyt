import AppKit

/// 极简 Markdown 语法高亮器，基于正则。
/// 不追求完美，只是给源码模式一个可读的视觉效果。
final class MarkdownHighlighter {

    private struct Rule {
        let regex: NSRegularExpression
        let color: NSColor
        let bold: Bool
        let italic: Bool
    }

    private let rules: [Rule]

    init() {
        // 颜色取自 Xcode dark theme，浅色模式下也能看
        let headingColor   = NSColor.systemBlue
        let emphasisColor  = NSColor.systemPurple
        let codeColor      = NSColor.systemPink
        let linkColor      = NSColor.systemTeal
        let quoteColor     = NSColor.systemGray
        let listColor      = NSColor.systemOrange

        func re(_ p: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            return (try? NSRegularExpression(pattern: p, options: options))
                ?? NSRegularExpression()
        }

        rules = [
            // 标题 (# 到 ######)
            Rule(regex: re("^#{1,6} .*$", options: [.anchorsMatchLines]),
                 color: headingColor, bold: true, italic: false),
            // 引用块
            Rule(regex: re("^>.*$", options: [.anchorsMatchLines]),
                 color: quoteColor, bold: false, italic: true),
            // 列表项 - * + 或数字
            Rule(regex: re("^\\s*([-*+]|\\d+\\.)\\s", options: [.anchorsMatchLines]),
                 color: listColor, bold: true, italic: false),
            // 代码块围栏 ```
            Rule(regex: re("^```.*$", options: [.anchorsMatchLines]),
                 color: codeColor, bold: false, italic: false),
            // 行内代码 `xxx`
            Rule(regex: re("`[^`\\n]+`"),
                 color: codeColor, bold: false, italic: false),
            // 粗体 **xxx**
            Rule(regex: re("\\*\\*[^*\\n]+\\*\\*"),
                 color: emphasisColor, bold: true, italic: false),
            // 斜体 *xxx* (避免和粗体冲突，简单处理)
            Rule(regex: re("(?<!\\*)\\*[^*\\n]+\\*(?!\\*)"),
                 color: emphasisColor, bold: false, italic: true),
            // 链接 [text](url)
            Rule(regex: re("\\[[^\\]\\n]+\\]\\([^)\\n]+\\)"),
                 color: linkColor, bold: false, italic: false),
            // 图片 ![alt](url)
            Rule(regex: re("!\\[[^\\]\\n]*\\]\\([^)\\n]+\\)"),
                 color: linkColor, bold: false, italic: false),
            // 删除线 ~~xxx~~
            Rule(regex: re("~~[^~\\n]+~~"),
                 color: quoteColor, bold: false, italic: false),
        ]
    }

    func apply(to storage: NSTextStorage) {
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        // 先清掉之前的 link attribute，避免删除 `]( )` 后残留
        storage.removeAttribute(.link, range: full)

        for rule in rules {
            rule.regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let r = match?.range else { return }
                storage.addAttribute(.foregroundColor, value: rule.color, range: r)
                if rule.bold || rule.italic {
                    let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: rule.bold ? .bold : .regular)
                    var traits: NSFontDescriptor.SymbolicTraits = []
                    if rule.italic { traits.insert(.italic) }
                    let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
                    let font = NSFont(descriptor: descriptor, size: 14) ?? baseFont
                    storage.addAttribute(.font, value: font, range: r)
                }
            }
        }

        // 给 [text](url) 形式的链接加 .link 属性，让 NSTextView 原生支持 cmd+click。
        // 注意：这一步独立于上面的着色规则。
        applyLinkAttributes(to: storage, in: text, range: full)
    }

    private func applyLinkAttributes(to storage: NSTextStorage, in text: String, range: NSRange) {
        // 匹配 [text](url) ，捕获 url
        guard let linkRegex = try? NSRegularExpression(
            pattern: "\\[[^\\]\\n]+\\]\\(([^)\\n\\s]+)(?:\\s+\"[^\"]*\")?\\)"
        ) else { return }
        linkRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 2 else { return }
            let urlRange = m.range(at: 1)
            guard urlRange.location != NSNotFound else { return }
            var urlString = (text as NSString).substring(with: urlRange)
            // 没有 scheme 时补 https://，与预览模式 normalizeHref 逻辑一致
            if urlString.range(of: "^[a-zA-Z][a-zA-Z0-9+\\-.]*:", options: .regularExpression) == nil,
               !urlString.hasPrefix("#") {
                if urlString.hasPrefix("//") {
                    urlString = "https:" + urlString
                } else {
                    urlString = "https://" + urlString
                }
            }
            guard let url = URL(string: urlString) else { return }
            storage.addAttribute(.link, value: url, range: m.range)
        }
    }
}
