// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HelpCenterBackupMacApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HelpCenterBackupApp", targets: ["HelpCenterBackupApp"])
    ],
    targets: [
        .executableTarget(
            name: "HelpCenterBackupApp",
            path: "Sources/HelpCenterBackupApp"
        )
    ]
)
