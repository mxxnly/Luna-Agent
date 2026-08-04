// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "LunaAgentMenu",
  platforms: [.macOS(.v10_14)],
  products: [
    .executable(name: "LunaAgentMenu", targets: ["LunaAgentMenu"])
  ],
  targets: [
    .executableTarget(
      name: "LunaAgentMenu",
      path: "Sources",
      swiftSettings: [
        .unsafeFlags(["-parse-as-library"])
      ]
    )
  ]
)
