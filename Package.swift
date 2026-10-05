// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BedrockForFoundationModels",
    platforms: [
        .iOS("27.2"), .macOS("27.2"), .visionOS("27.2"), .watchOS("27.2"),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BedrockForFoundationModels",
            targets: ["BedrockForFoundationModels"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/awslabs/aws-sdk-swift",
            from: "1.8.4", 
        )
    ],
    targets: [
        .target(
            name: "BedrockForFoundationModels",
            dependencies: [
                .product(name: "AWSBedrockRuntime", package: "aws-sdk-swift")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .executableTarget(
            name: "Examples",
            dependencies: [
                "BedrockForFoundationModels",
                .product(name: "AWSSTS", package: "aws-sdk-swift")
            ],
            path: "Examples"
        ),
        .testTarget(
            name: "BedrockForFoundationModelsTests",
            dependencies: ["BedrockForFoundationModels"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
