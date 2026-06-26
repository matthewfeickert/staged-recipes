#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail -o xtrace

# Diagnostic: record the toolchain the conda activation provides.
echo "toolchain: CC=${CC:-} CXX=${CXX:-} FC=${FC:-} HOST=${HOST:-} CPU_COUNT=${CPU_COUNT:-}"

# CalcHEP is a run-in-place package: ``sbin/setPath`` and ``getFlags`` bake an
# absolute install path into include/rootDir.h, FlagsForMake (CALCHEP=...),
# FlagsForSh, and several bin/* helper scripts, and the engine JIT-compiles
# generated process code at run time using the compiler recorded in FlagsForSh.
# Build the tree directly under its final location so the embedded paths equal
# the build prefix and conda's automatic prefix replacement (text + binary)
# makes the package relocatable.
CALCHEP_HOME="${PREFIX}/share/calchep"
mkdir -p "${CALCHEP_HOME}"

# Locate the source root (getFlags sits at the top level) robustly, whether or
# not the archive's leading directory was stripped on extraction.
SRC_ROOT="$(dirname "$(find . -maxdepth 2 -name getFlags -type f | head -1)")"
cp -a "${SRC_ROOT}/." "${CALCHEP_HOME}/"
cd "${CALCHEP_HOME}"

# Pre-seed FlagsForSh so getFlags sources it (instead of probing a bare ``gcc``)
# and builds with the conda-forge toolchain. Force "blind" mode (LX11/HX11 empty)
# so there is no X11/xorg dependency; all symbolic, numeric and batch
# functionality works -- only the interactive graphical menu is unavailable (the
# calchep-gui output re-links it against X11).
#
# -fcommon is REQUIRED: CalcHEP's C relies on tentative definitions of globals in
# shared headers, which GCC >= 10 (-fno-common by default) rejects as multiple
# definitions at link time.
#
# GCC >= 14 promotes several legacy-C diagnostics to errors by default; CalcHEP's
# older C trips them (e.g. a pthread_create thread routine typed `int *` rather
# than `void *`). Downgrade them back to warnings so the upstream sources build
# unmodified. (C-only; not added to CXXFLAGS.)
LEGACY_C="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=implicit-int"
cat > FlagsForSh <<EOF
CC="${CC}"
CFLAGS="${CFLAGS:-} -fsigned-char -std=gnu99 -fPIC -fcommon ${LEGACY_C}"
HX11=
LX11=""
lDL="-rdynamic -ldl"
SHARED="-shared"
SONAME=
SO=so
SNUM=
FC="${FC}"
FFLAGS="${FFLAGS:-} -fno-automatic"
lFort="-lgfortran"
CXX="${CXX}"
CXXFLAGS="${CXXFLAGS:-} -fPIC -fcommon"
RANLIB="${RANLIB:-ranlib}"
MAKE=make
lQuad="-lquadmath"
export CC CFLAGS lDL LX11 SHARED SONAME SO FC FFLAGS RANLIB CXX CXXFLAGS lFort lQuad MAKE
EOF

# A pristine tree has no work/bin symlink; the build creates it. Guard re-runs.
rm -f work/bin

# Serial build: the recursive c_source build has cross-subdirectory link-order
# dependencies and is not -j safe. </dev/null guards any stray interactive read.
make </dev/null

# Re-assert the install path in include/rootDir.h and the bin/* helper scripts.
./sbin/setPath "${CALCHEP_HOME}"

# The work/bin symlink points at the absolute build-prefix bin/ and would not
# survive relocation; drop it (mkWORKdir recreates a correct one per work dir).
rm -f work/bin
