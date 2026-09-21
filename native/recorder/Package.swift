// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "JottyRecorder",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "jotty-recorder", targets: ["JottyRecorder"])
  ],
  targets: [
    .executableTarget(
      name: "JottyRecorder",
      exclude: ["Info.plist"],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "Sources/JottyRecorder/Info.plist",
        ])
      ]
    ),
    .testTarget(
      name: "JottyRecorderTests",
      dependencies: ["JottyRecorder"]
    ),
  ]
)
