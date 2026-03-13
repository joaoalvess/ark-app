#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor/BlackHole"
BUILD_ROOT="${ARKAUDIO_BUILD_ROOT:-${ROOT_DIR}/build/ArkAudioDriver}"
BUILD_PRODUCTS_DIR="${BUILD_ROOT}/products"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
PKG_ROOT_DIR="${BUILD_ROOT}/pkgroot"
PKG_SCRIPTS_DIR="${BUILD_ROOT}/scripts"
RESOURCES_DIR="${BUILD_ROOT}/resources"
ARTIFACTS_DIR="${BUILD_ROOT}/artifacts"
APP_RESOURCE_PKG="${ROOT_DIR}/Ark/Resources/ArkAudioDriver.pkg"
APP_RESOURCE_METADATA="${ROOT_DIR}/Ark/Resources/ArkAudioDriver.build-info.json"

DRIVER_BASE_NAME="${ARKAUDIO_DRIVER_BASE_NAME:-ArkAudio}"
DRIVER_PRODUCT_NAME="${ARKAUDIO_PRODUCT_NAME:-ArkAudio2ch}"
DRIVER_EXECUTABLE_NAME="${ARKAUDIO_EXECUTABLE_NAME:-ArkAudio}"
DRIVER_DISPLAY_NAME="${ARKAUDIO_DISPLAY_NAME:-ArkAudio 2ch}"
DRIVER_BUNDLE_ID="${ARKAUDIO_BUNDLE_ID:-com.ark.audio.ArkAudio2ch}"
DRIVER_MANUFACTURER="${ARKAUDIO_MANUFACTURER:-Ark}"
DRIVER_ICON_NAME="${ARKAUDIO_ICON_NAME:-ArkAudio.icns}"
DRIVER_CHANNELS="${ARKAUDIO_CHANNELS:-2}"
DRIVER_VERSION="${ARKAUDIO_VERSION:-$(tr -d '\n' < "${VENDOR_DIR}/VERSION")}"
COPY_TO_APP_RESOURCES="${ARKAUDIO_COPY_TO_APP_RESOURCES:-1}"
SHAREABLE_BUILD="${ARKAUDIO_SHAREABLE:-0}"

DRIVER_SIGN_IDENTITY="${ARKAUDIO_CODESIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${ARKAUDIO_INSTALLER_IDENTITY:-}"

if [[ ! -d "${VENDOR_DIR}/BlackHole.xcodeproj" ]]; then
  echo "Missing vendored BlackHole source at ${VENDOR_DIR}" >&2
  exit 1
fi

if [[ "${SHAREABLE_BUILD}" == "1" ]]; then
  if [[ -z "${DRIVER_SIGN_IDENTITY}" || -z "${INSTALLER_SIGN_IDENTITY}" ]]; then
    echo "Shareable builds require ARKAUDIO_CODESIGN_IDENTITY and ARKAUDIO_INSTALLER_IDENTITY." >&2
    exit 1
  fi
fi

rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_PRODUCTS_DIR}" "${DERIVED_DATA_DIR}" "${PKG_ROOT_DIR}" "${PKG_SCRIPTS_DIR}" "${RESOURCES_DIR}" "${ARTIFACTS_DIR}"

build_driver() {
  local build_mode="$1"
  local -a command=(
    xcodebuild
    -project "${VENDOR_DIR}/BlackHole.xcodeproj"
    -scheme BlackHole
    -configuration Release
    -derivedDataPath "${DERIVED_DATA_DIR}"
    "CONFIGURATION_BUILD_DIR=${BUILD_PRODUCTS_DIR}"
    "PRODUCT_NAME=${DRIVER_PRODUCT_NAME}"
    "EXECUTABLE_NAME=${DRIVER_EXECUTABLE_NAME}"
    "PRODUCT_BUNDLE_IDENTIFIER=${DRIVER_BUNDLE_ID}"
    "MARKETING_VERSION=${DRIVER_VERSION}"
    "GCC_PREPROCESSOR_DEFINITIONS=\$(inherited) DEBUG=0 kNumber_Of_Channels=${DRIVER_CHANNELS} kPlugIn_BundleID=\\\"${DRIVER_BUNDLE_ID}\\\" kDriver_Name=\\\"${DRIVER_BASE_NAME}\\\" kManufacturer_Name=\\\"${DRIVER_MANUFACTURER}\\\" kPlugIn_Icon=\\\"${DRIVER_ICON_NAME}\\\""
  )

  if [[ "${build_mode}" == "unsigned" ]]; then
    command+=("CODE_SIGNING_ALLOWED=NO")
  fi

  "${command[@]}"
}

build_mode="unsigned"
if [[ -n "${DRIVER_SIGN_IDENTITY}" ]]; then
  build_mode="signed"
fi

build_driver "${build_mode}"

DRIVER_BUNDLE_PATH="${BUILD_PRODUCTS_DIR}/${DRIVER_PRODUCT_NAME}.driver"
DRIVER_PLIST="${DRIVER_BUNDLE_PATH}/Contents/Info.plist"
PACKAGE_COMPONENT_PATH="${ARTIFACTS_DIR}/ArkAudioComponent.pkg"
OUTPUT_PKG_PATH="${ARTIFACTS_DIR}/ArkAudioDriver.pkg"
BUILD_INFO_PATH="${ARTIFACTS_DIR}/ArkAudioDriver.build-info.json"

if [[ ! -d "${DRIVER_BUNDLE_PATH}" ]]; then
  echo "Expected built driver at ${DRIVER_BUNDLE_PATH}" >&2
  exit 1
fi

plugin_uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
sed -i '' "s/e395c745-4eea-4d94-bb92-46224221047c/${plugin_uuid}/g" "${DRIVER_PLIST}"

if [[ -f "${DRIVER_BUNDLE_PATH}/Contents/Resources/BlackHole.icns" ]]; then
  cp "${DRIVER_BUNDLE_PATH}/Contents/Resources/BlackHole.icns" "${DRIVER_BUNDLE_PATH}/Contents/Resources/${DRIVER_ICON_NAME}"
  rm "${DRIVER_BUNDLE_PATH}/Contents/Resources/BlackHole.icns"
fi

find "${DRIVER_BUNDLE_PATH}" -name '._*' -delete

if [[ -n "${DRIVER_SIGN_IDENTITY}" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --sign "${DRIVER_SIGN_IDENTITY}" \
    "${DRIVER_BUNDLE_PATH}"
fi

cat > "${PKG_SCRIPTS_DIR}/preinstall" <<'EOF'
#!/bin/sh
set -e
mkdir -p /Library/Audio/Plug-Ins/HAL
chown root:wheel /Library/Audio/Plug-Ins/HAL
EOF

cat > "${PKG_SCRIPTS_DIR}/postinstall" <<'EOF'
#!/bin/sh
set -e
chown -R root:wheel /Library/Audio/Plug-Ins/HAL/ArkAudio*ch.driver
EOF

chmod 755 "${PKG_SCRIPTS_DIR}/preinstall" "${PKG_SCRIPTS_DIR}/postinstall"
cp -R "${DRIVER_BUNDLE_PATH}" "${PKG_ROOT_DIR}/${DRIVER_PRODUCT_NAME}.driver"
find "${PKG_ROOT_DIR}" -name '._*' -delete

pkgbuild_args=(
  --root "${PKG_ROOT_DIR}"
  --scripts "${PKG_SCRIPTS_DIR}"
  --identifier "${DRIVER_BUNDLE_ID}"
  --version "${DRIVER_VERSION}"
  --install-location /Library/Audio/Plug-Ins/HAL
  "${PACKAGE_COMPONENT_PATH}"
)

if [[ -n "${INSTALLER_SIGN_IDENTITY}" ]]; then
  pkgbuild_args=(--sign "${INSTALLER_SIGN_IDENTITY}" "${pkgbuild_args[@]}")
fi

pkgbuild "${pkgbuild_args[@]}"

cat > "${RESOURCES_DIR}/welcome.html" <<EOF
<!doctype html>
<html lang="en">
  <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px;">
    <h1>${DRIVER_DISPLAY_NAME}</h1>
    <p>This installer adds the Ark virtual audio driver used by Ark to capture system audio.</p>
    <p>After installation, open Audio MIDI Setup and create a Multi-Output Device with your speakers and ${DRIVER_DISPLAY_NAME}.</p>
  </body>
</html>
EOF

cat > "${RESOURCES_DIR}/conclusion.html" <<EOF
<!doctype html>
<html lang="en">
  <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px;">
    <h1>Next step</h1>
    <p>Restart macOS if the driver does not appear immediately, then validate the routing in Ark settings.</p>
  </body>
</html>
EOF

cat > "${RESOURCES_DIR}/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<installer-gui-script minSpecVersion="2">
  <title>${DRIVER_DISPLAY_NAME} ${DRIVER_VERSION}</title>
  <welcome file="welcome.html"/>
  <license file="${VENDOR_DIR}/LICENSE"/>
  <conclusion file="conclusion.html"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <pkg-ref id="${DRIVER_BUNDLE_ID}"/>
  <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
  <volume-check>
    <allowed-os-versions>
      <os-version min="10.10"/>
    </allowed-os-versions>
  </volume-check>
  <choices-outline>
    <line choice="${DRIVER_BUNDLE_ID}"/>
  </choices-outline>
  <choice id="${DRIVER_BUNDLE_ID}" visible="true" title="${DRIVER_DISPLAY_NAME}" start_selected="true">
    <pkg-ref id="${DRIVER_BUNDLE_ID}"/>
  </choice>
  <pkg-ref id="${DRIVER_BUNDLE_ID}" version="${DRIVER_VERSION}" onConclusion="RequireRestart">${PACKAGE_COMPONENT_PATH}</pkg-ref>
</installer-gui-script>
EOF

productbuild_args=(
  --distribution "${RESOURCES_DIR}/distribution.xml"
  --resources "${RESOURCES_DIR}"
  --package-path "${ARTIFACTS_DIR}"
  "${OUTPUT_PKG_PATH}"
)

if [[ -n "${INSTALLER_SIGN_IDENTITY}" ]]; then
  productbuild_args=(--sign "${INSTALLER_SIGN_IDENTITY}" "${productbuild_args[@]}")
fi

productbuild "${productbuild_args[@]}"

cat > "${BUILD_INFO_PATH}" <<EOF
{
  "name": "${DRIVER_DISPLAY_NAME}",
  "bundle_id": "${DRIVER_BUNDLE_ID}",
  "product_name": "${DRIVER_PRODUCT_NAME}",
  "executable_name": "${DRIVER_EXECUTABLE_NAME}",
  "version": "${DRIVER_VERSION}",
  "source_repo": "https://github.com/ExistentialAudio/BlackHole",
  "source_tag": "v0.6.1",
  "local_only": $([[ -z "${DRIVER_SIGN_IDENTITY}" || -z "${INSTALLER_SIGN_IDENTITY}" ]] && echo "true" || echo "false"),
  "generated_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

if [[ "${COPY_TO_APP_RESOURCES}" == "1" ]]; then
  cp "${OUTPUT_PKG_PATH}" "${APP_RESOURCE_PKG}"
  cp "${BUILD_INFO_PATH}" "${APP_RESOURCE_METADATA}"
fi

echo "Built ${OUTPUT_PKG_PATH}"
if [[ "${COPY_TO_APP_RESOURCES}" == "1" ]]; then
  echo "Updated ${APP_RESOURCE_PKG}"
fi
