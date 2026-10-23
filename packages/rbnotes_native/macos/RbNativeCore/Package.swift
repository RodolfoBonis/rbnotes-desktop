// swift-tools-version: 5.9
import PackageDescription

// Auxiliary package that compiles ONLY the pure, Flutter-independent logic in
// the plugin's `Core` directory so it can be exercised with `swift test`.
//
// `Sources/RbNativeCore/*.swift` are symlinks to the canonical sources at
// `../rbnotes_native/Sources/rbnotes_native/Core/`, which CocoaPods compiles
// into the Flutter plugin (via its `**/*.swift` glob). There is no code
// duplication: these tests run against the production source files.
let package = Package(
  name: "RbNativeCore",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "RbNativeCore", targets: ["RbNativeCore"])
  ],
  targets: [
    .target(name: "RbNativeCore"),
    .testTarget(
      name: "RbNativeCoreTests",
      dependencies: ["RbNativeCore"]
    ),
  ]
)
