// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LexCleaner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "LexCleanerCore",
            targets: ["LexCleanerCore"]
        ),
        .executable(
            name: "LexCleanerCoreTestRunner",
            targets: ["LexCleanerCoreTestRunner"]
        ),
        .executable(
            name: "LexCleanerScanTestRunner",
            targets: ["LexCleanerScanTestRunner"]
        ),
        .executable(
            name: "LexCleanerClassificationTestRunner",
            targets: ["LexCleanerClassificationTestRunner"]
        ),
        .executable(
            name: "LexCleanerCleanupTestRunner",
            targets: ["LexCleanerCleanupTestRunner"]
        ),
        .executable(
            name: "LexCleanerMonitoringTestRunner",
            targets: ["LexCleanerMonitoringTestRunner"]
        ),
        .executable(
            name: "LexCleanerHardwareTestRunner",
            targets: ["LexCleanerHardwareTestRunner"]
        ),
        .executable(
            name: "LexCleanerDiskAnalysisTestRunner",
            targets: ["LexCleanerDiskAnalysisTestRunner"]
        ),
        .executable(
            name: "LexCleanerAppManagerTestRunner",
            targets: ["LexCleanerAppManagerTestRunner"]
        ),
        .executable(
            name: "LexCleanerSystemToolsTestRunner",
            targets: ["LexCleanerSystemToolsTestRunner"]
        )
    ],
    dependencies: [
        // Swift Testing is an explicit package dependency so `swift test` is
        // reproducible outside an Xcode project that may provide it implicitly.
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            exact: "6.2.4"
        )
    ],
    targets: [
        .target(
            name: "LexCleanerCore",
            path: "Sources/LexCleanerCore"
        ),
        .executableTarget(
            name: "LexCleanerCoreTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerCoreTestRunner"
        ),
        .executableTarget(
            name: "LexCleanerScanTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerScanTestRunner"
        ),
        .executableTarget(
            name: "LexCleanerClassificationTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerClassificationTestRunner"
        ),
        .executableTarget(
            name: "LexCleanerCleanupTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerCleanupTestRunner"
        ),
        .executableTarget(
            name: "LexCleanerMonitoringTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerMonitoringTestRunner"
        ),
        .executableTarget(
            name: "LexCleanerHardwareTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerHardwareTestRunner"
        ),
        .executableTarget(
            name: "LexCleanerDiskAnalysisTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerDiskAnalysisTestRunner"
        ),
        .executableTarget(
            name: "LexCleanerAppManagerTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerAppManagerTestRunner"
        ),
        .executableTarget(
            name: "LexCleanerSystemToolsTestRunner",
            dependencies: ["LexCleanerCore"],
            path: "Tests/LexCleanerSystemToolsTestRunner"
        ),
        .testTarget(
            name: "LexCleanerCoreTests",
            dependencies: [
                "LexCleanerCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/LexCleanerCoreTests"
        )
    ]
)
