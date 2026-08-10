// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AccountingQuestionKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "AccountingQuestionKit", targets: ["AccountingQuestionKit"]),
        .executable(name: "aqvalidate", targets: ["aqvalidate"])
    ],
    targets: [
        .target(name: "AccountingQuestionKit"),
        .executableTarget(name: "aqvalidate", dependencies: ["AccountingQuestionKit"]),
        .testTarget(
            name: "AccountingQuestionKitTests",
            dependencies: ["AccountingQuestionKit"]
        )
    ]
)
