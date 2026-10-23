#
# rbnotes_native — native macOS plugin for RbNotes.
# Run `pod lib lint rbnotes_native.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rbnotes_native'
  s.version          = '0.0.1'
  s.summary          = 'Native macOS plugin for RbNotes (recording, whisper.cpp, dictation).'
  s.description      = <<-DESC
Permissions, dual-source audio recording (AVAudioEngine + ScreenCaptureKit),
local whisper.cpp (Metal) transcription and global dictation for RbNotes.
                       DESC
  s.homepage         = 'https://github.com/rodolfodebonis/rbnotes-desktop'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Rodolfo de Bonis' => 'nicolyejady@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files = 'rbnotes_native/Sources/rbnotes_native/**/*.swift'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '13.0'
  s.swift_version = '5.9'

  # whisper.cpp (Metal, shaders embedded) built from source by
  # scripts/build_whisper.sh. Not committed to git; see README.
  s.vendored_frameworks = 'Frameworks/whisper.xcframework'

  # System frameworks used by the Swift sources.
  s.frameworks = [
    'AVFoundation', 'ScreenCaptureKit', 'CoreGraphics', 'CoreMedia',
    'Carbon', 'AppKit', 'Accelerate', 'Metal', 'CoreAudio', 'AudioToolbox'
  ]

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_ENABLE_MODULES' => 'YES',
    # Link the vendored whisper framework (CocoaPods copies the matching slice
    # into PODS_XCFRAMEWORKS_BUILD_DIR, already on FRAMEWORK_SEARCH_PATHS).
    'OTHER_LDFLAGS' => '-framework whisper',
    # On a fresh build Xcode may compile this target's Swift before the
    # "[CP] Copy XCFrameworks" phase extracts whisper into
    # PODS_XCFRAMEWORKS_BUILD_DIR (seen on Xcode 26.6 CI: "Unable to resolve
    # module dependency: 'whisper'"). Also search the source slice, which exists
    # before the build starts (scripts/build_whisper.sh runs at pod install).
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "${PODS_XCFRAMEWORKS_BUILD_DIR}/rbnotes_native" "${PODS_TARGET_SRCROOT}/Frameworks/whisper.xcframework/macos-arm64_x86_64" "${PODS_TARGET_SRCROOT}/Frameworks/whisper.xcframework/macos-arm64"',
    'SWIFT_ENABLE_EXPLICIT_MODULES' => 'NO',
  }

  # Self-healing: build the whisper framework before compiling if it is
  # missing (e.g. a fresh checkout). The Podfile also runs this at evaluation
  # time so vendored_frameworks resolves; this phase is a fallback for IDE
  # builds. No-op when the framework already exists.
  s.script_phase = {
    :name => 'Build whisper.cpp framework',
    :script => 'bash "${PODS_TARGET_SRCROOT}/../scripts/build_whisper.sh"',
    :execution_position => :before_compile
  }
end
