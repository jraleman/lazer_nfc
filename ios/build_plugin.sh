#!/usr/bin/env bash
#
# Builds the LaZer NFC Core NFC plugin and stages it where Godot looks for it.
#
# Godot scans <host project>/ios/plugins one level deep, so a game folder cannot
# own that path. This script therefore builds inside games/lazer_nfc/ios/build
# and copies the finished artefacts into the host project, mirroring the way the
# Android build stages its AAR into android/bin.
#
# Usage:
#   ./build_plugin.sh --godot-source ~/src/godot           # debug + release
#   GODOT_SOURCE=~/src/godot ./build_plugin.sh --config release
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOST_DIR="$(cd "${GAME_DIR}/../.." && pwd)"

BUILD_DIR="${SCRIPT_DIR}/build"
STAGE_DIR="${HOST_DIR}/ios/plugins/lazer_nfc"
MIN_IOS="${LAZER_NFC_MIN_IOS:-15.0}"
GODOT_SOURCE="${GODOT_SOURCE:-}"
CONFIGS=("debug" "release")

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--godot-source) GODOT_SOURCE="${2:-}"; shift 2 ;;
		--config) CONFIGS=("${2:-}"); shift 2 ;;
		--clean) rm -rf "${BUILD_DIR}"; shift ;;
		-h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
done

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || die "iOS plugins can only be compiled on macOS."
command -v xcrun >/dev/null 2>&1 || die "xcrun not found. Install Xcode and run xcode-select --install."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install the full Xcode, not just the command line tools."

[[ -n "${GODOT_SOURCE}" ]] || die "Set GODOT_SOURCE or pass --godot-source to a Godot 4.7.2-stable checkout."
GODOT_SOURCE="$(cd "${GODOT_SOURCE}" && pwd)"
[[ -f "${GODOT_SOURCE}/core/object/object.h" ]] || die "${GODOT_SOURCE} is not a Godot source checkout."

if [[ -f "${GODOT_SOURCE}/version.py" ]]; then
	source_version="$(python3 - "${GODOT_SOURCE}/version.py" <<'PY'
import sys
scope = {}
exec(open(sys.argv[1]).read(), scope)
print(f"{scope['major']}.{scope['minor']}.{scope.get('patch', 0)}")
PY
)"
	info "Godot source reports version ${source_version}"
	case "${source_version}" in
		4.7.2) ;;
		*)
			if [[ "${LAZER_NFC_ALLOW_VERSION_MISMATCH:-0}" == "1" ]]; then
				printf '\033[33mwarning:\033[0m building against Godot %s, not 4.7.2.\n' "${source_version}" >&2
			else
				die "Expected a Godot 4.7.2 checkout; found ${source_version}. The plugin is statically linked into the export template, so the engine headers must match it exactly. Set LAZER_NFC_ALLOW_VERSION_MISMATCH=1 to override."
			fi
			;;
	esac
fi

# ---------------------------------------------------------------------------
# Generated headers
#
# core/version.h includes core/version_generated.gen.h, which only exists after
# a SCons run. Shadow the missing generated headers in a scratch include dir so
# a clean checkout works without building the whole engine first.
# ---------------------------------------------------------------------------

GEN_DIR="${BUILD_DIR}/gen"
mkdir -p "${GEN_DIR}/core" "${GEN_DIR}/modules"

if [[ ! -f "${GODOT_SOURCE}/core/version_generated.gen.h" ]]; then
	info "Generating core/version_generated.gen.h shim"
	python3 - "${GODOT_SOURCE}/version.py" "${GEN_DIR}/core/version_generated.gen.h" <<'PY'
import sys
scope = {}
exec(open(sys.argv[1]).read(), scope)
patch = scope.get("patch", 0)
with open(sys.argv[2], "w") as out:
    out.write("#pragma once\n")
    out.write(f'#define GODOT_VERSION_SHORT_NAME "{scope["short_name"]}"\n')
    out.write(f'#define GODOT_VERSION_NAME "{scope["name"]}"\n')
    out.write(f'#define GODOT_VERSION_MAJOR {scope["major"]}\n')
    out.write(f'#define GODOT_VERSION_MINOR {scope["minor"]}\n')
    out.write(f"#define GODOT_VERSION_PATCH {patch}\n")
    out.write(f'#define GODOT_VERSION_STATUS "{scope["status"]}"\n')
    out.write("#define GODOT_VERSION_STATUS_VERSION 0\n")
    out.write('#define GODOT_VERSION_BUILD "official"\n')
    out.write('#define GODOT_VERSION_MODULE_CONFIG ""\n')
    out.write(f'#define GODOT_VERSION_WEBSITE "{scope.get("website", "")}"\n')
    out.write(f'#define GODOT_VERSION_DOCS_BRANCH "{scope.get("docs", "stable")}"\n')
    out.write('#define GODOT_VERSION_DOCS_URL "https://docs.godotengine.org/en/" GODOT_VERSION_DOCS_BRANCH\n')
PY
fi

if [[ ! -f "${GODOT_SOURCE}/modules/modules_enabled.gen.h" ]]; then
	printf '#pragma once\n' > "${GEN_DIR}/modules/modules_enabled.gen.h"
fi

# The remaining generated headers this translation unit pulls in are lists of
# #defines that are empty in a default build, so an empty shim is faithful.
for generated in core/disabled_classes.gen.h; do
	if [[ ! -f "${GODOT_SOURCE}/${generated}" ]]; then
		mkdir -p "${GEN_DIR}/$(dirname "${generated}")"
		printf '#pragma once\n' > "${GEN_DIR}/${generated}"
	fi
done

info "If clang still reports a missing *.gen.h, run scons platform=ios in ${GODOT_SOURCE} once to generate the full set."

# ---------------------------------------------------------------------------
# Compilation
# ---------------------------------------------------------------------------

SOURCES=("${SCRIPT_DIR}/src/lazer_nfc.mm" "${SCRIPT_DIR}/src/lazer_nfc_module.mm")

INCLUDES=(-I"${GEN_DIR}" -I"${GODOT_SOURCE}")
for extra in platform/ios platform/apple_embedded drivers; do
	[[ -d "${GODOT_SOURCE}/${extra}" ]] && INCLUDES+=(-I"${GODOT_SOURCE}/${extra}")
done

# These must mirror the defines the matching export template was built with;
# DEBUG_ENABLED in particular changes engine object layout.
COMMON_DEFINES=(
	-DIOS_ENABLED -DAPPLE_EMBEDDED_ENABLED -DUNIX_ENABLED -DCOREAUDIO_ENABLED
	-DTYPED_METHOD_BIND -DPTRCALL_ENABLED -DNEED_LONG_INT -DTHREADS_ENABLED
)
COMMON_FLAGS=(
	-std=gnu++17 -stdlib=libc++ -fobjc-arc -fblocks -fmodules
	-fno-exceptions -Wall -Wno-unused-parameter
)

compile_slice() {
	local config="$1" triple="$2" sdk="$3" slice_dir="$4"
	local sysroot
	sysroot="$(xcrun --sdk "${sdk}" --show-sdk-path)"

	local defines=("${COMMON_DEFINES[@]}")
	local opt
	if [[ "${config}" == "debug" ]]; then
		defines+=(-DDEBUG_ENABLED -DDEBUG_MEMORY_ALLOC -DDISABLE_FORCED_INLINE)
		opt=(-g -O0)
	else
		defines+=(-DNDEBUG)
		opt=(-O2)
	fi

	mkdir -p "${slice_dir}"
	local objects=()
	for source in "${SOURCES[@]}"; do
		local object="${slice_dir}/$(basename "${source%.mm}").o"
		xcrun clang++ -c "${source}" -o "${object}" \
			-target "${triple}" -isysroot "${sysroot}" \
			"${COMMON_FLAGS[@]}" "${opt[@]}" "${defines[@]}" "${INCLUDES[@]}"
		objects+=("${object}")
	done
	xcrun libtool -static -o "${slice_dir}/liblazer_nfc.a" "${objects[@]}"
}

for config in "${CONFIGS[@]}"; do
	case "${config}" in
		debug|release) ;;
		*) die "unknown config: ${config} (expected debug or release)" ;;
	esac

	info "Building ${config} slices"
	device_dir="${BUILD_DIR}/${config}/ios-arm64"
	sim_arm_dir="${BUILD_DIR}/${config}/sim-arm64"
	sim_x86_dir="${BUILD_DIR}/${config}/sim-x86_64"
	sim_dir="${BUILD_DIR}/${config}/ios-simulator"

	compile_slice "${config}" "arm64-apple-ios${MIN_IOS}" iphoneos "${device_dir}"
	compile_slice "${config}" "arm64-apple-ios${MIN_IOS}-simulator" iphonesimulator "${sim_arm_dir}"
	compile_slice "${config}" "x86_64-apple-ios${MIN_IOS}-simulator" iphonesimulator "${sim_x86_dir}"

	mkdir -p "${sim_dir}"
	xcrun lipo -create \
		"${sim_arm_dir}/liblazer_nfc.a" "${sim_x86_dir}/liblazer_nfc.a" \
		-output "${sim_dir}/liblazer_nfc.a"

	framework="${BUILD_DIR}/lazer_nfc.${config}.xcframework"
	rm -rf "${framework}"
	xcodebuild -create-xcframework \
		-library "${device_dir}/liblazer_nfc.a" \
		-library "${sim_dir}/liblazer_nfc.a" \
		-output "${framework}" >/dev/null
	info "Built ${framework##*/}"
done

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------

info "Staging into ${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
cp "${SCRIPT_DIR}/lazer_nfc.gdip" "${STAGE_DIR}/lazer_nfc.gdip"
for config in "${CONFIGS[@]}"; do
	rm -rf "${STAGE_DIR}/lazer_nfc.${config}.xcframework"
	cp -R "${BUILD_DIR}/lazer_nfc.${config}.xcframework" "${STAGE_DIR}/"
done

# lazer_nfc.gdip names an unsuffixed binary, which Godot only resolves per
# target when both suffixed xcframeworks exist. A half-staged plugin either
# fails to export or silently links yesterday's other configuration, and the
# two cannot be mirrored because DEBUG_ENABLED changes engine object layout.
for config in debug release; do
	if [[ ! -d "${STAGE_DIR}/lazer_nfc.${config}.xcframework" ]]; then
		die "lazer_nfc.${config}.xcframework is not staged. Run without --config so both configurations are built."
	fi
done

cat <<EOF

LaZer NFC iOS plugin staged.

  Plugin folder : ${STAGE_DIR}
  Next steps    : open the host project, tick LazerNfc in the
                  "iOS - LaZer NFC" preset, and export the Xcode project.

Reading tags additionally requires the "Near Field Communication Tag Reading"
capability on App ID com.deskcansaw.lazernfc. Godot cannot set that for you.
EOF
