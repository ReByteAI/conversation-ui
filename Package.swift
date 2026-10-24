// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConversationUI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ConversationUI", targets: ["ConversationUI"]),
        // The response renderer both apps show replies with (iOS only; see Sources/ResponseText/README.md).
        .library(name: "ResponseText", targets: ["ResponseText"]),
    ],
    dependencies: [
        .package(url: "https://github.com/colinc86/MathJaxSwift", from: "3.4.0"),
        .package(url: "https://github.com/swhitty/SwiftDraw", from: "0.20.1"),
    ],
    targets: [
        .target(name: "ConversationUI"),
        .target(name: "EnrichedMarkdownCppShim",
            sources: ["cpp/SwiftParserShim.cpp", "core/parser/MD4CParser.cpp", "core/md4c/md4c.c"],
            publicHeadersPath: "cpp",
            cSettings: [.define("MD4C_USE_UTF8", to: "1")],
            cxxSettings: [.headerSearchPath("core/parser"), .headerSearchPath("core/md4c")]),
        // Vendored Swift 5 code; the apps themselves build in Swift 6.
        .target(name: "ResponseText",
            dependencies: ["EnrichedMarkdownCppShim", "MathJaxSwift", "SwiftDraw"],
            exclude: ["LICENSE", "LICENSE.impo", "README.md", "UPSTREAM.md"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ConversationUITests", dependencies: ["ConversationUI"]),
        .testTarget(name: "ResponseTextTests", dependencies: ["ResponseText"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ],
    cxxLanguageStandard: .cxx17
)
