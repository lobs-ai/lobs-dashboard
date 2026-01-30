// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "LobsDashboard",
  platforms: [
    .macOS(.13)
  ],
  products: [
    .executable(name: "lobs-dashboard", targets: ["LobsDashboard"])
  ],
  targets: [
    .executableTarget(
      name: "LobsDashboard"
    )
  ]
)
