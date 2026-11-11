// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "image_gallery_saver",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "image-gallery-saver", targets: ["image_gallery_saver"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "image_gallery_saver",
            dependencies: [],
            path: "Sources/image_gallery_saver"
        )
    ]
)
