import UIKit

/// Hosts can supply their product icon set without changing menu behavior.
@MainActor public enum MarkdownMenuIcons {
    public static var imageProvider: ((String) -> UIImage?)?

    static func image(_ name: String) -> UIImage? {
        imageProvider?(name) ?? UIImage(systemName: name)
    }
}
