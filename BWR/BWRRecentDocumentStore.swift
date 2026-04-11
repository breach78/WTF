import Foundation

enum BWRRecentDocumentStore {
    private static let bookmarkKey = "bwr.lastOpenedBookmark"

    static func remember(url: URL) {
        guard let bookmarkData = try? url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }

    static func resolve() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false

        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            clear()
            return nil
        }

        if isStale {
            remember(url: url)
        }

        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if targetEnvironment(macCatalyst)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if targetEnvironment(macCatalyst)
        return [.withSecurityScope, .withoutUI]
        #else
        return [.withoutUI]
        #endif
    }
}
