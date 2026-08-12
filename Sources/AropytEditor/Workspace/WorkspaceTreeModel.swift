import Foundation

final class WorkspaceTreeNode: NSObject {
    fileprivate(set) var url: URL
    let isDirectory: Bool
    weak var parent: WorkspaceTreeNode?
    fileprivate var loadedChildren: [WorkspaceTreeNode]?

    init(url: URL, isDirectory: Bool, parent: WorkspaceTreeNode? = nil) {
        self.url = url.standardizedFileURL
        self.isDirectory = isDirectory
        self.parent = parent
    }

    var name: String { url.lastPathComponent }
    var childrenAreLoaded: Bool { loadedChildren != nil }
}

/// Lazily materializes one directory level at a time for NSOutlineView. A
/// refresh discards the cached subtree so the next read comes from disk.
final class WorkspaceTreeModel {
    private(set) var root: WorkspaceTreeNode
    let fileSystem: WorkspaceFileSystem

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        let fileSystem = try WorkspaceFileSystem(rootURL: rootURL, fileManager: fileManager)
        self.fileSystem = fileSystem
        self.root = WorkspaceTreeNode(url: fileSystem.rootURL, isDirectory: true)
    }

    func children(of node: WorkspaceTreeNode) throws -> [WorkspaceTreeNode] {
        guard node.isDirectory else { return [] }
        if let children = node.loadedChildren { return children }
        let children = try fileSystem.contents(of: node.url).map {
            WorkspaceTreeNode(url: $0.url, isDirectory: $0.isDirectory, parent: node)
        }
        node.loadedChildren = children
        return children
    }

    func refresh(_ node: WorkspaceTreeNode? = nil) {
        (node ?? root).loadedChildren = nil
    }

    func loadedNode(at url: URL) -> WorkspaceTreeNode? {
        let url = url.standardizedFileURL
        return loadedNode(at: url, below: root)
    }

    func node(at url: URL) throws -> WorkspaceTreeNode? {
        let url = url.standardizedFileURL
        guard fileSystem.contains(url) else { return nil }
        if url == root.url { return root }

        let relativeComponents = url.pathComponents.dropFirst(root.url.pathComponents.count)
        var current = root
        for component in relativeComponents {
            guard let child = try children(of: current).first(where: { $0.name == component }) else {
                return nil
            }
            current = child
        }
        return current
    }

    func updateURLs(afterMoving oldURL: URL, to newURL: URL) {
        updateURLs(below: root,
                   oldComponents: oldURL.standardizedFileURL.pathComponents,
                   newURL: newURL.standardizedFileURL)
    }

    private func loadedNode(at url: URL, below node: WorkspaceTreeNode) -> WorkspaceTreeNode? {
        if node.url == url { return node }
        for child in node.loadedChildren ?? [] {
            if let result = loadedNode(at: url, below: child) { return result }
        }
        return nil
    }

    private func updateURLs(below node: WorkspaceTreeNode,
                            oldComponents: [String],
                            newURL: URL) {
        let nodeComponents = node.url.pathComponents
        if nodeComponents.count >= oldComponents.count,
           Array(nodeComponents.prefix(oldComponents.count)) == oldComponents {
            let suffix = nodeComponents.dropFirst(oldComponents.count)
            node.url = suffix.reduce(newURL) { $0.appendingPathComponent($1) }
        }
        for child in node.loadedChildren ?? [] {
            updateURLs(below: child, oldComponents: oldComponents, newURL: newURL)
        }
    }
}
