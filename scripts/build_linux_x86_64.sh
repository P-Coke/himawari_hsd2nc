#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_BIN_DIR="${ROOT_DIR}/src/himawari_hsd2nc/bin/linux-x86_64"
BUNDLE_DIR="${ROOT_DIR}/build_tools/linux_runtime_builder"
FORTRAN_SRC_DIR="${ROOT_DIR}/src/fortran/src"

if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "ERROR: missing ${BUNDLE_DIR}" >&2
  exit 1
fi
if [[ ! -d "${FORTRAN_SRC_DIR}" ]]; then
  echo "ERROR: missing ${FORTRAN_SRC_DIR}" >&2
  exit 1
fi

rm -rf "${BUNDLE_DIR}/src"
mkdir -p "${BUNDLE_DIR}/src"
cp -f "${FORTRAN_SRC_DIR}"/* "${BUNDLE_DIR}/src/"

pushd "${BUNDLE_DIR}" >/dev/null
chmod +x build_linux.sh
# Keep environment in CI/job for faster retries.
CLEAN_ENV=0 BUNDLE_OFFLINE=1 ./build_linux.sh
popd >/dev/null

rm -rf "${PKG_BIN_DIR}"
mkdir -p "${PKG_BIN_DIR}"
cp -r "${BUNDLE_DIR}/offline_package/bin" "${PKG_BIN_DIR}/bin"
cp -r "${BUNDLE_DIR}/offline_package/lib" "${PKG_BIN_DIR}/lib"
cp "${BUNDLE_DIR}/offline_package/run_AHI.sh" "${PKG_BIN_DIR}/run_AHI.sh"
cp "${BUNDLE_DIR}/offline_package/run_AHI_FAST.sh" "${PKG_BIN_DIR}/run_AHI_FAST.sh"
cp "${BUNDLE_DIR}/offline_package/run_AHI_FAST_ROI.sh" "${PKG_BIN_DIR}/run_AHI_FAST_ROI.sh"

echo "linux-x86_64 runtime staged at: ${PKG_BIN_DIR}"
ls -lh "${PKG_BIN_DIR}/bin"
