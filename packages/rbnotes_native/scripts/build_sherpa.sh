#!/usr/bin/env bash
#
# Assembles the sherpa-onnx speaker-diarization dependency into two macOS
# xcframeworks consumed by the CocoaPods podspec via `vendored_frameworks`:
#
#   Frameworks/sherpa_onnx.xcframework   (the C API + the Swift module header)
#   Frameworks/onnxruntime.xcframework   (the ONNX Runtime it links against)
#
# Reproducible and no binaries are committed to git: the official sherpa-onnx
# universal2 *shared* release is downloaded at a PINNED version and verified
# against a PINNED SHA-256, then the already-@rpath dylibs are wrapped into
# versioned frameworks (no compilation). Mirrors scripts/build_whisper.sh; the
# Podfile runs this at `pod install` and the podspec has a build phase fallback.
#
# Usage:
#   scripts/build_sherpa.sh          # build if missing (idempotent)
#   FORCE=1 scripts/build_sherpa.sh  # always rebuild
set -euo pipefail

SHERPA_REF="${SHERPA_REF:-v2.0.0}"
# sherpa-onnx-${SHERPA_REF}-osx-universal2-shared.tar.bz2 (x86_64 + arm64).
SHERPA_SHA256="${SHERPA_SHA256:-32bc7a4a463ba35e2447428439062f3b1794cdb929596dfb04ccde383126708f}"
SHERPA_SIZE="${SHERPA_SIZE:-43458941}"
MACOS_MIN_OS_VERSION="${MACOS_MIN_OS_VERSION:-13.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FRAMEWORK_DIR="${PKG_DIR}/macos/Frameworks"
SHERPA_XCF="${FRAMEWORK_DIR}/sherpa_onnx.xcframework"
ORT_XCF="${FRAMEWORK_DIR}/onnxruntime.xcframework"
BUILD_ROOT="${SHERPA_BUILD_DIR:-${PKG_DIR}/.sherpa-build}"

TARBALL_NAME="sherpa-onnx-${SHERPA_REF}-osx-universal2-shared"
TARBALL="${BUILD_ROOT}/${TARBALL_NAME}.tar.bz2"
EXTRACT_DIR="${BUILD_ROOT}/${TARBALL_NAME}"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_REF}/${TARBALL_NAME}.tar.bz2"

log() { printf '\033[1;35m[build_sherpa]\033[0m %s\n' "$*"; }

if [[ -d "${SHERPA_XCF}" && -d "${ORT_XCF}" && -z "${FORCE:-}" ]]; then
  log "sherpa_onnx/onnxruntime xcframeworks already present — skipping (FORCE=1 to rebuild)."
  exit 0
fi

mkdir -p "${BUILD_ROOT}"

# --- Fetch + verify pinned release ------------------------------------------
need_download=1
if [[ -f "${TARBALL}" ]]; then
  actual="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
  [[ "${actual}" == "${SHERPA_SHA256}" ]] && need_download=0
fi
if [[ "${need_download}" == "1" ]]; then
  log "Downloading sherpa-onnx ${SHERPA_REF} (osx-universal2-shared)..."
  curl -fL --retry 3 -o "${TARBALL}" "${URL}"
fi

actual_sha="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
actual_size="$(stat -f%z "${TARBALL}")"
if [[ "${actual_sha}" != "${SHERPA_SHA256}" ]]; then
  echo "error: SHA-256 mismatch (${actual_sha} != ${SHERPA_SHA256})." >&2
  exit 1
fi
if [[ "${actual_size}" != "${SHERPA_SIZE}" ]]; then
  echo "error: size mismatch (${actual_size} != ${SHERPA_SIZE})." >&2
  exit 1
fi
log "Verified SHA-256 and size."

rm -rf "${EXTRACT_DIR}"
tar xjf "${TARBALL}" -C "${BUILD_ROOT}"

LIB_DIR="${EXTRACT_DIR}/lib"
INCLUDE_HEADER="${EXTRACT_DIR}/include/sherpa-onnx/c-api/c-api.h"
ORT_DYLIB="${LIB_DIR}/libonnxruntime.dylib"
CAPI_DYLIB="${LIB_DIR}/libsherpa-onnx-c-api.dylib"
for f in "${INCLUDE_HEADER}" "${ORT_DYLIB}" "${CAPI_DYLIB}"; do
  [[ -f "${f}" ]] || { echo "error: expected file missing: ${f}" >&2; exit 1; }
done

# --- Wrap a universal2 dylib into a versioned macOS framework ----------------
# $1 = framework name, $2 = source dylib, $3 = (optional) header to expose.
make_framework() {
  local name="$1" src="$2" header="${3:-}"
  local fw="${BUILD_ROOT}/frameworks/${name}.framework"
  rm -rf "${fw}"
  mkdir -p "${fw}/Versions/A/Headers" "${fw}/Versions/A/Modules" "${fw}/Versions/A/Resources"
  ln -sf A "${fw}/Versions/Current"
  ln -sf Versions/Current/Headers "${fw}/Headers"
  ln -sf Versions/Current/Modules "${fw}/Modules"
  ln -sf Versions/Current/Resources "${fw}/Resources"
  ln -sf "Versions/Current/${name}" "${fw}/${name}"

  cp "${src}" "${fw}/Versions/A/${name}"
  install_name_tool -id "@rpath/${name}.framework/Versions/A/${name}" \
    "${fw}/Versions/A/${name}"

  if [[ "${name}" == "sherpa_onnx" ]]; then
    # Point the C API at the onnxruntime framework's binary (both frameworks
    # land in the app's Frameworks dir, which is on @rpath).
    install_name_tool -change "@rpath/libonnxruntime.dylib" \
      "@rpath/onnxruntime.framework/Versions/A/onnxruntime" \
      "${fw}/Versions/A/${name}"
  fi

  if [[ -n "${header}" ]]; then
    cp "${header}" "${fw}/Versions/A/Headers/${name}.h"
    cat > "${fw}/Versions/A/Modules/module.modulemap" << EOF
framework module ${name} {
    umbrella header "${name}.h"
    export *
    module * { export * }
}
EOF
  fi

  cat > "${fw}/Versions/A/Resources/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>${name}</string>
    <key>CFBundleIdentifier</key><string>com.k2fsa.sherpa.${name}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>${name}</string>
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
  echo "${fw}"
}

log "Wrapping dylibs into frameworks..."
rm -rf "${BUILD_ROOT}/frameworks"
ORT_FW="$(make_framework onnxruntime "${ORT_DYLIB}")"
SHERPA_FW="$(make_framework sherpa_onnx "${CAPI_DYLIB}" "${INCLUDE_HEADER}")"

# --- Package the xcframeworks ------------------------------------------------
log "Creating xcframeworks..."
mkdir -p "${FRAMEWORK_DIR}"
rm -rf "${ORT_XCF}" "${SHERPA_XCF}"
xcodebuild -create-xcframework -framework "${ORT_FW}" -output "${ORT_XCF}" >/dev/null
xcodebuild -create-xcframework -framework "${SHERPA_FW}" -output "${SHERPA_XCF}" >/dev/null

log "Done: ${SHERPA_XCF} + ${ORT_XCF}"
