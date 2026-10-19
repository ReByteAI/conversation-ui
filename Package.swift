// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConversationUI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ConversationUI", targets: ["ConversationUI"])],
    targets: [.target(name: "ConversationUI"), .testTarget(name: "ConversationUITests", dependencies: ["ConversationUI"])]
)
