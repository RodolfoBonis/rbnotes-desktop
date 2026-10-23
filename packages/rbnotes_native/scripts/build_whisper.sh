#!/usr/bin/env bash
#
# Builds whisper.cpp (with Metal, embedded shaders) into a self-contained
# `whisper.xcframework` for macOS, consumed by the CocoaPods podspec via
# `vendored_frameworks`.
#
# Reproducible: the whisper.cpp source is cloned at a pinned tag and the Metal
# shader library is embedded into the binary (GGML_METAL_EMBED_LIBRARY=ON), so
# the framework has no external runtime dependency. No binaries are committed
# to git; this script is run on first `pod install` (see podspec prepare_command)
# and in CI.
#
# Usage:
#   scripts/build_whisper.sh            # build if missing (idempotent)
#   FORCE=1 scripts/build_whisper.sh    # always rebuild
#   WHISPER_ARCHS="arm64 x86_64" ...    # default: universal (arm64 x86_64), needed by release builds
#
set -euo pipefail

WHISPER_REF="${WHISPER_REF:-v1.7.6}"
MACOS_MIN_OS_VERSION="${MACOS_MIN_OS_VERSION:-13.0}"
WHISPER_ARCHS="${WHISPER_ARCHS:-arm64 x86_64}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FRAMEWORK_DIR="${PKG_DIR}/macos/Frameworks"
XCFRAMEWORK="${FRAMEWORK_DIR}/whisper.xcframework"
BUILD_ROOT="${WHISPER_BUILD_DIR:-${PKG_DIR}/.whisper-build}"
SRC="${BUILD_ROOT}/whisper.cpp"

log() { printf '\033[1;34m[build_whisper]\033[0m %s\n' "$*"; }

if [[ -d "${XCFRAMEWORK}" && -z "${FORCE:-}" ]]; then
  log "whisper.xcframework already present — skipping (set FORCE=1 to rebuild)."
  exit 0
fi

command -v cmake >/dev/null 2>&1 || {
  echo "error: cmake is required (brew install cmake)." >&2
  exit 1
}

mkdir -p "${BUILD_ROOT}"

# --- Fetch pinned source -----------------------------------------------------
if [[ -d "${SRC}" && ! -d "${SRC}/.git" ]]; then
  log "Discarding incomplete source dir (no .git)..."
  rm -rf "${SRC}"
fi
if [[ ! -d "${SRC}/.git" ]]; then
  log "Cloning whisper.cpp ${WHISPER_REF}..."
  git clone --depth 1 --branch "${WHISPER_REF}" \
    https://github.com/ggerganov/whisper.cpp "${SRC}"
else
  log "Reusing existing clone; checking out ${WHISPER_REF}..."
  git -C "${SRC}" fetch --depth 1 origin "tag" "${WHISPER_REF}" 2>/dev/null || true
  git -C "${SRC}" checkout -q "${WHISPER_REF}"
fi

cd "${SRC}"

BUILD_DIR="build-macos"
FRAMEWORK_NAME="whisper"
rm -rf "${BUILD_DIR}"

arch_list=(${WHISPER_ARCHS})
cmake_archs="$(IFS=';'; echo "${arch_list[*]}")"

# --- Configure & build static libs (Metal embedded, no CoreML) ---------------
log "Configuring (archs: ${WHISPER_ARCHS}, min macOS ${MACOS_MIN_OS_VERSION})..."
cmake -B "${BUILD_DIR}" -G Xcode \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DWHISPER_COREML=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_METAL_USE_BF16=OFF \
  -DGGML_BLAS_DEFAULT=ON \
  -DGGML_OPENMP=OFF \
  -DGGML_NATIVE=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_MIN_OS_VERSION}" \
  -DCMAKE_OSX_ARCHITECTURES="${cmake_archs}" \
  -DCMAKE_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument" \
  -DCMAKE_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument" \
  -S .

log "Building (Release)..."
cmake --build "${BUILD_DIR}" --config Release -- -quiet

# --- Assemble a versioned macOS framework ------------------------------------
log "Assembling ${FRAMEWORK_NAME}.framework..."
FW="${BUILD_DIR}/framework/${FRAMEWORK_NAME}.framework"
rm -rf "${FW}"
mkdir -p "${FW}/Versions/A/Headers" "${FW}/Versions/A/Modules" "${FW}/Versions/A/Resources"
ln -sf A "${FW}/Versions/Current"
ln -sf Versions/Current/Headers "${FW}/Headers"
ln -sf Versions/Current/Modules "${FW}/Modules"
ln -sf Versions/Current/Resources "${FW}/Resources"
ln -sf "Versions/Current/${FRAMEWORK_NAME}" "${FW}/${FRAMEWORK_NAME}"

HEADER_PATH="${FW}/Versions/A/Headers"
cp include/whisper.h           "${HEADER_PATH}/"
cp ggml/include/ggml.h         "${HEADER_PATH}/"
cp ggml/include/ggml-alloc.h   "${HEADER_PATH}/"
cp ggml/include/ggml-backend.h "${HEADER_PATH}/"
cp ggml/include/ggml-metal.h   "${HEADER_PATH}/"
cp ggml/include/ggml-cpu.h     "${HEADER_PATH}/"
cp ggml/include/ggml-blas.h    "${HEADER_PATH}/"
cp ggml/include/gguf.h         "${HEADER_PATH}/"

cat > "${FW}/Versions/A/Modules/module.modulemap" << 'EOF'
framework module whisper {
    header "whisper.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
EOF

cat > "${FW}/Versions/A/Resources/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>whisper</string>
    <key>CFBundleIdentifier</key><string>org.ggml.whisper</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>whisper</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>${MACOS_MIN_OS_VERSION}</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>DTPlatformName</key><string>macosx</string>
    <key>DTSDKName</key><string>macosx${MACOS_MIN_OS_VERSION}</string>
</dict>
</plist>
EOF

# --- Combine static libs into a single dynamic library -----------------------
log "Combining static libraries into a dynamic framework binary..."
REL="Release"
LIBS=(
  "${BUILD_DIR}/src/${REL}/libwhisper.a"
  "${BUILD_DIR}/ggml/src/${REL}/libggml.a"
  "${BUILD_DIR}/ggml/src/${REL}/libggml-base.a"
  "${BUILD_DIR}/ggml/src/${REL}/libggml-cpu.a"
  "${BUILD_DIR}/ggml/src/ggml-metal/${REL}/libggml-metal.a"
  "${BUILD_DIR}/ggml/src/ggml-blas/${REL}/libggml-blas.a"
)
for lib in "${LIBS[@]}"; do
  [[ -f "${lib}" ]] || { echo "error: expected static lib missing: ${lib}" >&2; exit 1; }
done

TEMP_DIR="${BUILD_DIR}/temp"
mkdir -p "${TEMP_DIR}"
# Multiple architectures cause benign "same member name" warnings — suppressed.
libtool -static -o "${TEMP_DIR}/combined.a" "${LIBS[@]}" 2>/dev/null

arch_flags=""
for arch in "${arch_list[@]}"; do arch_flags+=" -arch ${arch}"; done

OUTPUT_LIB="${FW}/Versions/A/${FRAMEWORK_NAME}"
xcrun -sdk macosx clang++ -dynamiclib \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  ${arch_flags} \
  -mmacosx-version-min="${MACOS_MIN_OS_VERSION}" \
  -Wl,-force_load,"${TEMP_DIR}/combined.a" \
  -framework Foundation -framework Metal -framework Accelerate \
  -install_name "@rpath/whisper.framework/Versions/Current/whisper" \
  -o "${OUTPUT_LIB}"
rm -rf "${TEMP_DIR}"

# --- Package the xcframework -------------------------------------------------
log "Creating whisper.xcframework..."
rm -rf "${XCFRAMEWORK}"
mkdir -p "${FRAMEWORK_DIR}"
xcodebuild -create-xcframework \
  -framework "${FW}" \
  -output "${XCFRAMEWORK}"

log "Done: ${XCFRAMEWORK}"
