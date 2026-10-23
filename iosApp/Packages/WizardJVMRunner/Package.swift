// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WizardJVMRunner",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "WizardJVMRunner", targets: ["WizardJVMRunner"]),
    ],
    targets: [
        .target(
            name: "CWizardJVMBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedFramework("CoreGraphics", .when(platforms: [.iOS, .macOS])),
                .linkedFramework("CoreText", .when(platforms: [.iOS, .macOS])),
                .linkedFramework("ImageIO", .when(platforms: [.iOS, .macOS])),
                .linkedFramework("JavaScriptCore", .when(platforms: [.iOS, .macOS])),
            ]
        ),
        .target(
            name: "WizardJVMRunner",
            dependencies: ["CWizardJVMBridge"]
        ),
    ]
)
