// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "telegraphe-app",
    defaultLocalization: "fr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Telegraphe", type: .dynamic, targets: ["Telegraphe"]),
        .library(name: "TelegrapheCore", targets: ["TelegrapheCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.13"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0"),
        .package(url: "https://github.com/skiptools/skip-sql.git", from: "0.16.1"),
        .package(url: "https://github.com/skiptools/skip-keychain.git", from: "0.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
    ],
    targets: [
        .target(name: "Telegraphe", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            "TelegrapheCore",
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "TelegrapheCore", dependencies: [
            .product(name: "SkipSQL", package: "skip-sql"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "TelegrapheCoreTests", dependencies: [
            "TelegrapheCore",
            .product(name: "SkipSQL", package: "skip-sql"),
            .product(name: "SkipTest", package: "skip"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
