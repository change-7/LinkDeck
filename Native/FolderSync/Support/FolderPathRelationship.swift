import Foundation

enum FolderPathRelationship {
    static func relativePath(of childPath: String, inside parentPath: String) -> String? {
        relativePath(
            of: URL(fileURLWithPath: childPath),
            inside: URL(fileURLWithPath: parentPath)
        )
    }

    static func relativePath(of child: URL, inside parent: URL) -> String? {
        let childPath = child.resolvingSymlinksInPath().standardizedFileURL.path
        let parentPath = parent.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"

        guard childPath != parentPath, childPath.hasPrefix(prefix) else { return nil }
        return String(childPath.dropFirst(prefix.count))
    }
}
