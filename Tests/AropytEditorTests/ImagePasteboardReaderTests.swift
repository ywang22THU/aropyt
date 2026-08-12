import AppKit
import Testing
@testable import AropytEditor

@Suite("Image pasteboard reader", .serialized)
@MainActor
struct ImagePasteboardReaderTests {
    @Test func readsImageFileURLBeforeRenderedPasteboardImage() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("photo.png")
        try Self.pixelPNG.write(to: imageURL)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([imageURL as NSURL]))

        guard case .file(let result)? = ImagePasteboardReader.imageSource(from: pasteboard) else {
            Issue.record("Expected an image file URL")
            return
        }
        #expect(result == imageURL)
    }

    @Test func readsRawPNGAndIgnoresPlainText() throws {
        _ = NSApplication.shared
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        #expect(pasteboard.setData(Self.pixelPNG, forType: .png))

        guard case .data(let data, let filename)? = ImagePasteboardReader.imageSource(from: pasteboard) else {
            Issue.record("Expected PNG data")
            return
        }
        #expect(data == Self.pixelPNG)
        #expect(filename == "image.png")

        pasteboard.clearContents()
        #expect(pasteboard.setString("ordinary text", forType: .string))
        #expect(ImagePasteboardReader.imageSource(from: pasteboard) == nil)
    }

    private static let pixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
