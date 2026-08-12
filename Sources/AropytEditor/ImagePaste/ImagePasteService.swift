import Foundation
import UniformTypeIdentifiers

enum ImagePasteSource {
    case file(URL)
    case data(Data, suggestedFilename: String)
}

struct ImagePasteInsertion: Equatable {
    let markdown: String
    let markdownURL: String
    let imageURL: URL
    let copiedFileURL: URL?
}

final class ImagePasteService {
    enum PasteError: LocalizedError, Equatable {
        case sourceIsNotImage
        case sourceFileUnavailable
        case originalPathUnavailable
        case documentMustBeSaved
        case couldNotCreateResourceDirectory
        case couldNotCopyImage

        var errorDescription: String? {
            switch self {
            case .sourceIsNotImage:
                return L10n.tr(
                    "image.paste.error.not_image",
                    "The clipboard does not contain a supported image."
                )
            case .sourceFileUnavailable:
                return L10n.tr(
                    "image.paste.error.source_unavailable",
                    "The original image file is unavailable."
                )
            case .originalPathUnavailable:
                return L10n.tr(
                    "image.paste.error.original_path_unavailable",
                    "This clipboard image has no original file path. Choose a copy location in Image settings to paste it."
                )
            case .documentMustBeSaved:
                return L10n.tr(
                    "image.paste.error.unsaved_document",
                    "Save the Markdown document before copying images beside it."
                )
            case .couldNotCreateResourceDirectory:
                return L10n.tr(
                    "image.paste.error.create_directory",
                    "The image resource directory could not be created."
                )
            case .couldNotCopyImage:
                return L10n.tr(
                    "image.paste.error.copy_failed",
                    "The image could not be copied to the selected location."
                )
            }
        }
    }

    private let preferences: ImagePastePreferences
    private let fileManager: FileManager

    init(
        preferences: ImagePastePreferences = .shared,
        fileManager: FileManager = .default
    ) {
        self.preferences = preferences
        self.fileManager = fileManager
    }

    func makeInsertion(
        for source: ImagePasteSource,
        documentURL: URL?
    ) throws -> ImagePasteInsertion {
        switch preferences.destination {
        case .originalPath:
            return try insertionUsingOriginalPath(for: source)
        case .currentDirectory:
            return try insertionByCopying(
                source,
                documentURL: documentURL,
                relativeDirectory: nil
            )
        case .resourceDirectory:
            return try insertionByCopying(
                source,
                documentURL: documentURL,
                relativeDirectory: preferences.resourceDirectoryName
            )
        }
    }

    static func escapedImageURL(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.formUnion(CharacterSet(charactersIn: "-._~/!$&'*+,;=:@"))
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    private func insertionUsingOriginalPath(
        for source: ImagePasteSource
    ) throws -> ImagePasteInsertion {
        guard case .file(let originalURL) = source else {
            throw PasteError.originalPathUnavailable
        }
        let sourceURL = originalURL.standardizedFileURL
        try validateImageFile(at: sourceURL)
        return insertion(
            imageURL: sourceURL,
            copiedFileURL: nil,
            markdownPath: sourceURL.path
        )
    }

    private func insertionByCopying(
        _ source: ImagePasteSource,
        documentURL: URL?,
        relativeDirectory: String?
    ) throws -> ImagePasteInsertion {
        guard let documentURL, documentURL.isFileURL else {
            throw PasteError.documentMustBeSaved
        }
        let documentDirectory = documentURL.standardizedFileURL.deletingLastPathComponent()
        let destinationDirectory: URL
        if let relativeDirectory {
            destinationDirectory = relativeDirectory
                .split(separator: "/")
                .reduce(documentDirectory) {
                    $0.appendingPathComponent(String($1), isDirectory: true)
                }
            do {
                try fileManager.createDirectory(
                    at: destinationDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                throw PasteError.couldNotCreateResourceDirectory
            }
        } else {
            destinationDirectory = documentDirectory
        }

        let suggestedFilename: String
        let sourceFileURL: URL?
        let imageData: Data?
        switch source {
        case .file(let url):
            let url = url.standardizedFileURL
            try validateImageFile(at: url)
            suggestedFilename = url.lastPathComponent
            sourceFileURL = url
            imageData = nil
        case .data(let data, let filename):
            guard Self.isImageFilename(filename), !data.isEmpty else {
                throw PasteError.sourceIsNotImage
            }
            suggestedFilename = Self.safeFilename(filename)
            sourceFileURL = nil
            imageData = data
        }

        let destinationURL = uniqueDestinationURL(
            in: destinationDirectory,
            suggestedFilename: suggestedFilename,
            sourceURL: sourceFileURL
        )
        if destinationURL.standardizedFileURL != sourceFileURL?.standardizedFileURL {
            do {
                if let sourceFileURL {
                    try fileManager.copyItem(at: sourceFileURL, to: destinationURL)
                } else if let imageData {
                    try imageData.write(to: destinationURL, options: .atomic)
                }
            } catch {
                throw PasteError.couldNotCopyImage
            }
        }

        let relativePath: String
        if let relativeDirectory {
            relativePath = "./\(relativeDirectory)/\(destinationURL.lastPathComponent)"
        } else {
            relativePath = "./\(destinationURL.lastPathComponent)"
        }
        return insertion(
            imageURL: destinationURL,
            copiedFileURL: destinationURL.standardizedFileURL == sourceFileURL?.standardizedFileURL
                ? nil
                : destinationURL,
            markdownPath: relativePath
        )
    }

    private func insertion(
        imageURL: URL,
        copiedFileURL: URL?,
        markdownPath: String
    ) -> ImagePasteInsertion {
        let path = preferences.escapesImageURLs
            ? Self.escapedImageURL(markdownPath)
            : markdownPath
        return ImagePasteInsertion(
            markdown: "![](\(path))",
            markdownURL: path,
            imageURL: imageURL,
            copiedFileURL: copiedFileURL
        )
    }

    private func validateImageFile(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isReadableFile(atPath: url.path)
        else {
            throw PasteError.sourceFileUnavailable
        }
        guard Self.isImageFilename(url.lastPathComponent) else {
            throw PasteError.sourceIsNotImage
        }
    }

    private func uniqueDestinationURL(
        in directory: URL,
        suggestedFilename: String,
        sourceURL: URL?
    ) -> URL {
        let filename = Self.safeFilename(suggestedFilename)
        let initial = directory.appendingPathComponent(filename)
        if initial.standardizedFileURL == sourceURL?.standardizedFileURL
            || !fileManager.fileExists(atPath: initial.path) {
            return initial
        }

        let fileURL = URL(fileURLWithPath: filename)
        let pathExtension = fileURL.pathExtension
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        var suffix = 2
        while true {
            let candidateName = pathExtension.isEmpty
                ? "\(baseName)-\(suffix)"
                : "\(baseName)-\(suffix).\(pathExtension)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func safeFilename(_ filename: String) -> String {
        let filename = URL(fileURLWithPath: filename).lastPathComponent
        guard isImageFilename(filename) else { return "image.png" }
        return filename.isEmpty ? "image.png" : filename
    }

    private static func isImageFilename(_ filename: String) -> Bool {
        let pathExtension = URL(fileURLWithPath: filename).pathExtension
        guard !pathExtension.isEmpty,
              let type = UTType(filenameExtension: pathExtension)
        else { return false }
        return type.conforms(to: .image)
    }
}
