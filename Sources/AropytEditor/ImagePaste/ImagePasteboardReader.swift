import AppKit
import UniformTypeIdentifiers

enum ImagePasteboardReader {
    static func imageSource(from pasteboard: NSPasteboard) -> ImagePasteSource? {
        if let fileURL = imageFileURLs(from: pasteboard).first {
            return .file(fileURL)
        }
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return .data(pngData, suggestedFilename: "image.png")
        }
        guard
            let image = NSImage(pasteboard: pasteboard),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return .data(pngData, suggestedFilename: "image.png")
    }

    private static func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []
        return objects.compactMap { object in
            let url: URL?
            if let value = object as? URL {
                url = value
            } else if let value = object as? NSURL {
                url = value as URL
            } else {
                url = nil
            }
            guard let url, url.isFileURL, isImageURL(url) else { return nil }
            return url.standardizedFileURL
        }
    }

    private static func isImageURL(_ url: URL) -> Bool {
        guard
            !url.pathExtension.isEmpty,
            let type = UTType(filenameExtension: url.pathExtension)
        else { return false }
        return type.conforms(to: .image)
    }
}
