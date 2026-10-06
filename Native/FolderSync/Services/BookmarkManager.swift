import Foundation

enum BookmarkError: LocalizedError {
    case staleBookmark(String)
    case inaccessibleFolder(String)
    case accessDenied(String)
    case invalidBookmark(String)

    var errorDescription: String? {
        switch self {
        case .staleBookmark(let path): AppText.staleBookmark(path)
        case .inaccessibleFolder(let path): AppText.inaccessibleFolder(path)
        case .accessDenied(let path): AppText.accessDenied(path)
        case .invalidBookmark(let path): AppText.invalidBookmark(path)
        }
    }
}

enum BookmarkManager {
    static func resolve(_ reference: FolderReference) throws -> URL {
        do {
            return try resolve(reference, options: [.withSecurityScope])
        } catch BookmarkError.staleBookmark {
            throw BookmarkError.staleBookmark(reference.displayPath)
        } catch {
            do {
                return try resolve(reference, options: [])
            } catch BookmarkError.staleBookmark {
                throw BookmarkError.staleBookmark(reference.displayPath)
            } catch {
                throw BookmarkError.invalidBookmark(reference.displayPath)
            }
        }
    }

    private static func resolve(
        _ reference: FolderReference,
        options: URL.BookmarkResolutionOptions
    ) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: reference.bookmarkData,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else { throw BookmarkError.staleBookmark(reference.displayPath) }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BookmarkError.inaccessibleFolder(reference.displayPath)
        }
        return url
    }
}
