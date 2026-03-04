#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
BUILD_DIR="${SCRIPT_DIR}/build"
OUT_DIR="${SCRIPT_DIR}/bin"
OFFLINE_DIR="${SCRIPT_DIR}/offline_package"
OFFLINE_LIB_DIR="${OFFLINE_DIR}/lib"
OFFLINE_BIN_DIR="${OFFLINE_DIR}/bin"

# 1 = remove newly-installed build dependencies after successful build.
CLEAN_ENV="${CLEAN_ENV:-1}"
BUNDLE_OFFLINE="${BUNDLE_OFFLINE:-1}"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "ERROR: src directory not found: ${SRC_DIR}" >&2
  exit 1
fi

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: Need root or sudo to install dependencies." >&2
    exit 1
  fi
fi

PM=""
if command -v apt-get >/dev/null 2>&1; then
  PM="apt"
elif command -v dnf >/dev/null 2>&1; then
  PM="dnf"
elif command -v yum >/dev/null 2>&1; then
  PM="yum"
elif command -v zypper >/dev/null 2>&1; then
  PM="zypper"
elif command -v pacman >/dev/null 2>&1; then
  PM="pacman"
else
  echo "ERROR: Unsupported package manager. Install deps manually." >&2
  exit 1
fi

NEW_PKGS=()

install_deps_apt() {
  local pkgs=(build-essential gfortran pkg-config libnetcdf-dev libnetcdff-dev libhdf5-dev)
  local missing=()
  for p in "${pkgs[@]}"; do
    if ! dpkg -s "${p}" >/dev/null 2>&1; then
      missing+=("${p}")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y "${missing[@]}"
    NEW_PKGS+=("${missing[@]}")
  fi
}

install_deps_dnf() {
  local pkgs=(gcc gcc-c++ gcc-gfortran make pkgconf-pkg-config netcdf-devel netcdf-fortran-devel hdf5-devel)
  local missing=()
  for p in "${pkgs[@]}"; do
    if ! rpm -q "${p}" >/dev/null 2>&1; then
      missing+=("${p}")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    ${SUDO} dnf install -y "${missing[@]}"
    NEW_PKGS+=("${missing[@]}")
  fi
}

install_deps_yum() {
  local pkgs=(gcc gcc-c++ gcc-gfortran make pkgconfig netcdf-devel netcdf-fortran-devel hdf5-devel)
  local missing=()
  for p in "${pkgs[@]}"; do
    if ! rpm -q "${p}" >/dev/null 2>&1; then
      missing+=("${p}")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    ${SUDO} yum install -y "${missing[@]}"
    NEW_PKGS+=("${missing[@]}")
  fi
}

install_deps_zypper() {
  local pkgs=(gcc gcc-c++ gcc-fortran make pkg-config netcdf-devel netcdf-fortran-devel hdf5-devel)
  local missing=()
  for p in "${pkgs[@]}"; do
    if ! rpm -q "${p}" >/dev/null 2>&1; then
      missing+=("${p}")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    ${SUDO} zypper --non-interactive install "${missing[@]}"
    NEW_PKGS+=("${missing[@]}")
  fi
}

install_deps_pacman() {
  local pkgs=(base-devel gcc-fortran pkgconf netcdf-fortran hdf5)
  local missing=()
  for p in "${pkgs[@]}"; do
    if ! pacman -Q "${p}" >/dev/null 2>&1; then
      missing+=("${p}")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    ${SUDO} pacman -Sy --noconfirm "${missing[@]}"
    NEW_PKGS+=("${missing[@]}")
  fi
}

cleanup_deps() {
  if [[ "${CLEAN_ENV}" != "1" ]]; then
    return 0
  fi
  if [[ "${#NEW_PKGS[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "Cleaning newly installed build dependencies..."
  case "${PM}" in
    apt)
      ${SUDO} apt-get purge -y "${NEW_PKGS[@]}" || true
      ${SUDO} apt-get autoremove -y || true
      ${SUDO} apt-get clean || true
      ;;
    dnf)
      ${SUDO} dnf remove -y "${NEW_PKGS[@]}" || true
      ${SUDO} dnf clean all || true
      ;;
    yum)
      ${SUDO} yum remove -y "${NEW_PKGS[@]}" || true
      ${SUDO} yum clean all || true
      ;;
    zypper)
      ${SUDO} zypper --non-interactive remove "${NEW_PKGS[@]}" || true
      ;;
    pacman)
      ${SUDO} pacman -Rns --noconfirm "${NEW_PKGS[@]}" || true
      ;;
  esac
}

collect_runtime_libs() {
  local exe="$1"
  ldd "${exe}" | while read -r a b c _; do
    local libpath=""
    if [[ "${b:-}" == "=>" && "${c:-}" == /* ]]; then
      libpath="${c}"
    elif [[ "${a:-}" == /* ]]; then
      libpath="${a}"
    fi
    if [[ -z "${libpath}" || ! -f "${libpath}" ]]; then
      continue
    fi
    local base
    base="$(basename "${libpath}")"
    if [[ "${base}" =~ ^(ld-linux.*|libc\.so.*|libm\.so.*|libmvec\.so.*|libpthread\.so.*|librt\.so.*|libdl\.so.*|libresolv\.so.*)$ ]]; then
      continue
    fi
    cp -n "${libpath}" "${OFFLINE_LIB_DIR}/"
  done
}

write_launcher() {
  local target="$1"
  local out="$2"
  cat > "${out}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="\${ROOT}/lib:\${LD_LIBRARY_PATH:-}"
exec "\${ROOT}/bin/${target}" "\$@"
EOF
  chmod +x "${out}"
}

trap 'if [[ $? -ne 0 ]]; then echo "Build failed. Keeping environment for debugging."; fi' EXIT

echo "Detected package manager: ${PM}"
case "${PM}" in
  apt) install_deps_apt ;;
  dnf) install_deps_dnf ;;
  yum) install_deps_yum ;;
  zypper) install_deps_zypper ;;
  pacman) install_deps_pacman ;;
esac

mkdir -p "${BUILD_DIR}" "${OUT_DIR}"
rm -rf "${BUILD_DIR:?}"/*
cp -f "${SRC_DIR}"/* "${BUILD_DIR}/"
cd "${BUILD_DIR}"

F90FLAGS="-O3 -I. -ffree-line-length-0 -cpp -fopenmp"
CFLAGS="-O3 -I. -fopenmp"

NETCDF_FFLAGS="$(pkg-config --cflags netcdf-fortran 2>/dev/null || true)"
NETCDF_FLIBS="$(pkg-config --libs netcdf-fortran 2>/dev/null || true)"
if [[ -z "${NETCDF_FFLAGS}" || -z "${NETCDF_FLIBS}" ]]; then
  if command -v nf-config >/dev/null 2>&1; then
    NETCDF_FFLAGS="$(nf-config --fflags)"
    NETCDF_FLIBS="$(nf-config --flibs)"
  fi
fi

# Fallback for distros where pkg-config/nf-config is incomplete:
# locate netcdf.mod directly and inject include/library flags.
if [[ -z "${NETCDF_FFLAGS}" ]] || ! find /usr /usr/local -name netcdf.mod -print -quit >/dev/null 2>&1; then
  NETCDF_MOD_DIR="$(find /usr /usr/local -name netcdf.mod -print 2>/dev/null | head -n1 | xargs -r dirname || true)"
  if [[ -n "${NETCDF_MOD_DIR:-}" ]]; then
    NETCDF_FFLAGS="${NETCDF_FFLAGS} -I${NETCDF_MOD_DIR}"
  fi
fi
if [[ -z "${NETCDF_FLIBS}" ]]; then
  NETCDF_FLIBS="-lnetcdff -lnetcdf"
fi

if [[ -z "${NETCDF_FFLAGS}" ]]; then
  echo "ERROR: netcdf-fortran include flags not found; netcdf.mod is missing." >&2
  echo "Try: sudo apt-get install -y libnetcdf-dev libnetcdff-dev" >&2
  exit 1
fi

HDF5_CFLAGS="$(pkg-config --cflags hdf5 2>/dev/null || true)"
HDF5_LIBS="$(pkg-config --libs hdf5 2>/dev/null || true)"
if [[ -z "${HDF5_LIBS}" ]]; then
  HDF5_LIBS="-lhdf5 -lhdf5_hl -lhdf5_fortran -lhdf5hl_fortran"
fi

gfortran -c ${F90FLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} himawari.f90
gfortran -c ${F90FLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} himawari_headerinfo.f90
gfortran -c ${F90FLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} himawari_readheader.f90
gfortran -c ${F90FLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} himawari_utils.f90
gfortran -c ${F90FLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} himawari_nav.f90
gfortran -c ${F90FLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} himawari_readwrite.f90
gfortran -c ${F90FLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} AHI_Example.f90
gfortran -c ${F90FLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} AHI_FAST_Example.f90
gcc -c ${CFLAGS} ${NETCDF_FFLAGS} ${HDF5_CFLAGS} solpos.c

ar -rs libhimawari_util.a himawari.o himawari_headerinfo.o himawari_readheader.o himawari_utils.o himawari_nav.o himawari_readwrite.o solpos.o
ar -rs solar_util.a solpos.o

COMMON_OBJS="himawari.o himawari_headerinfo.o himawari_readheader.o himawari_utils.o himawari_nav.o himawari_readwrite.o"
COMMON_LIBS="${NETCDF_FLIBS} ${HDF5_LIBS} -lm -fopenmp"

gfortran -o AHI ${COMMON_OBJS} AHI_Example.o libhimawari_util.a solar_util.a ${COMMON_LIBS}
gfortran -o AHI_FAST ${COMMON_OBJS} AHI_FAST_Example.o libhimawari_util.a solar_util.a ${COMMON_LIBS}
gfortran -o AHI_FAST_ROI ${COMMON_OBJS} AHI_FAST_Example.o libhimawari_util.a solar_util.a ${COMMON_LIBS}

cp -f AHI AHI_FAST AHI_FAST_ROI "${OUT_DIR}/"
chmod +x "${OUT_DIR}/AHI" "${OUT_DIR}/AHI_FAST" "${OUT_DIR}/AHI_FAST_ROI"

# Simple smoke test: executable should run and print usage/error text.
set +e
"${OUT_DIR}/AHI_FAST_ROI" >/tmp/ahi_fast_roi_smoke.log 2>&1
SMOKE_RC=$?
set -e
if [[ ${SMOKE_RC} -eq 127 ]]; then
  echo "Smoke test failed: executable cannot run." >&2
  exit 1
fi
if ! grep -Eqi "usage|input|channel|No channels requested" /tmp/ahi_fast_roi_smoke.log; then
  echo "Smoke test warning: no expected usage text detected."
fi

echo "Build successful. Linux binaries:"
ls -lh "${OUT_DIR}/AHI" "${OUT_DIR}/AHI_FAST" "${OUT_DIR}/AHI_FAST_ROI"

if [[ "${BUNDLE_OFFLINE}" == "1" ]]; then
  rm -rf "${OFFLINE_DIR}"
  mkdir -p "${OFFLINE_BIN_DIR}" "${OFFLINE_LIB_DIR}"
  cp -f "${OUT_DIR}/AHI" "${OFFLINE_BIN_DIR}/"
  cp -f "${OUT_DIR}/AHI_FAST" "${OFFLINE_BIN_DIR}/"
  cp -f "${OUT_DIR}/AHI_FAST_ROI" "${OFFLINE_BIN_DIR}/"
  collect_runtime_libs "${OUT_DIR}/AHI"
  collect_runtime_libs "${OUT_DIR}/AHI_FAST"
  collect_runtime_libs "${OUT_DIR}/AHI_FAST_ROI"
  write_launcher "AHI" "${OFFLINE_DIR}/run_AHI.sh"
  write_launcher "AHI_FAST" "${OFFLINE_DIR}/run_AHI_FAST.sh"
  write_launcher "AHI_FAST_ROI" "${OFFLINE_DIR}/run_AHI_FAST_ROI.sh"
  tar -czf "${SCRIPT_DIR}/offline_package.tar.gz" -C "${SCRIPT_DIR}" offline_package
  echo "Offline package ready: ${SCRIPT_DIR}/offline_package.tar.gz"
fi

cleanup_deps
echo "Done."
