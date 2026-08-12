import Foundation

struct WorkspaceEntry: Equatable {
    let url: URL
    let isDirectory: Bool

    var name: String { url.lastPathComponent }
}

enum WorkspaceFileSystemError: LocalizedError, Equatable {
    case rootIsNotDirectory
    case itemIsOutsideWorkspace
    case itemIsNotDirectory
    case invalidName
    case itemAlreadyExists
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .rootIsNotDirectory:
            return L10n.tr("workspace.error.root_not_directory", "The workspace root is not a directory.")
        case .itemIsOutsideWorkspace:
            return L10n.tr("workspace.error.outside_root", "The item is outside the open directory.")
        case .itemIsNotDirectory:
            return L10n.tr("workspace.error.not_directory", "The selected item is not a directory.")
        case .invalidName:
            return L10n.tr("workspace.error.invalid_name", "Enter a valid name without path separators.")
        case .itemAlreadyExists:
            return L10n.tr("workspace.error.already_exists", "An item with that name already exists.")
        case .unsupportedFileType:
            return L10n.tr("workspace.error.unsupported_file", "Only Markdown (.md) files can be created or renamed here.")
        }
    }
}

/// All mutations performed by the workspace sidebar go through this type so
/// containment, filtering, and collision rules stay consistent.
final class WorkspaceFileSystem {
    let rootURL: URL

    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: self.rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceFileSystemError.rootIsNotDirectory
        }
    }

    func contents(of directoryURL: URL) throws -> [WorkspaceEntry] {
        let directoryURL = try validatedURL(directoryURL)
        guard isDirectory(directoryURL) else {
            throw WorkspaceFileSystemError.itemIsNotDirectory
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isHidden != true, values.isSymbolicLink != true else { return nil }
            if values.isDirectory == true {
                return WorkspaceEntry(url: url.standardizedFileURL, isDirectory: true)
            }
            guard values.isRegularFile == true, Self.isMarkdownFile(url) else { return nil }
            return WorkspaceEntry(url: url.standardizedFileURL, isDirectory: false)
        }.sorted(by: Self.entrySort)
    }

    func createMarkdownFile(in directoryURL: URL, named requestedName: String) throws -> URL {
        let directoryURL = try validatedDirectory(directoryURL)
        var name = try validatedName(requestedName)
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            name += ".md"
        }
        guard name.lowercased().hasSuffix(".md") else {
            throw WorkspaceFileSystemError.unsupportedFileType
        }
        let destination = try availableDestination(in: directoryURL, named: name)
        guard fileManager.createFile(atPath: destination.path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return destination
    }

    func createDirectory(in directoryURL: URL, named requestedName: String) throws -> URL {
        let directoryURL = try validatedDirectory(directoryURL)
        let name = try validatedName(requestedName)
        let destination = try availableDestination(in: directoryURL, named: name)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }

    func renameItem(at itemURL: URL, to requestedName: String) throws -> URL {
        let itemURL = try validatedURL(itemURL)
        guard itemURL != rootURL else { throw WorkspaceFileSystemError.itemIsOutsideWorkspace }
        var name = try validatedName(requestedName)
        if !isDirectory(itemURL) {
            if URL(fileURLWithPath: name).pathExtension.isEmpty {
                name += ".md"
            }
            guard name.lowercased().hasSuffix(".md") else {
                throw WorkspaceFileSystemError.unsupportedFileType
            }
        }
        let destination = try availableDestination(in: itemURL.deletingLastPathComponent(), named: name)
        try fileManager.moveItem(at: itemURL, to: destination)
        return destination
    }

    func deleteItem(at itemURL: URL) throws {
        let itemURL = try validatedURL(itemURL)
        guard itemURL != rootURL else { throw WorkspaceFileSystemError.itemIsOutsideWorkspace }
        try fileManager.removeItem(at: itemURL)
    }

    func contains(_ itemURL: URL) -> Bool {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let itemComponents = itemURL.standardizedFileURL.pathComponents
        return itemComponents.count >= rootComponents.count
            && Array(itemComponents.prefix(rootComponents.count)) == rootComponents
    }

    static func isMarkdownFile(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("md") == .orderedSame
    }

    private func validatedURL(_ url: URL) throws -> URL {
        let result = url.standardizedFileURL
        guard contains(result) else { throw WorkspaceFileSystemError.itemIsOutsideWorkspace }
        return result
    }

    private func validatedDirectory(_ url: URL) throws -> URL {
        let result = try validatedURL(url)
        guard isDirectory(result) else { throw WorkspaceFileSystemError.itemIsNotDirectory }
        return result
    }

    private func validatedName(_ requestedName: String) throws -> String {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains(":"),
              name.unicodeScalars.allSatisfy({ $0.value != 0 }) else {
            throw WorkspaceFileSystemError.invalidName
        }
        return name
    }

    private func availableDestination(in directoryURL: URL, named name: String) throws -> URL {
        let destination = directoryURL.appendingPathComponent(name).standardizedFileURL
        guard contains(destination) else { throw WorkspaceFileSystemError.itemIsOutsideWorkspace }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw WorkspaceFileSystemError.itemAlreadyExists
        }
        return destination
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func entrySort(_ lhs: WorkspaceEntry, _ rhs: WorkspaceEntry) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
