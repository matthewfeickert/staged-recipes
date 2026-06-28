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
#
# lQuad is left EMPTY. CalcHEP only links libquadmath when nType.h selects
# __float128 (the opt-in _QUADGCC_ high-precision mode); the default REAL=double
# build never references it -- upstream getFlags sets lQuad="" via the same
# _QUADGCC_ probe. Hardcoding -lquadmath added a spurious, unused NEEDED that is
# also non-portable (libquadmath is an x86_64-with-gcc library: clang/macOS ships
# none, and aarch64's native 128-bit long double makes it unnecessary). libgfortran
# -- a genuine dependency of the SLHA Fortran bridge below -- still pulls libquadmath
# in transitively on platforms whose libgfortran needs it (x86_64) and not elsewhere
# (aarch64), which is exactly the portable behaviour.
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
lQuad=
export CC CFLAGS lDL LX11 SHARED SONAME SO FC FFLAGS RANLIB CXX CXXFLAGS lFort lQuad MAKE
EOF

# A pristine tree has no work/bin symlink; the build creates it. Guard re-runs.
rm -f work/bin

# Serial build: the recursive c_source build has cross-subdirectory link-order
# dependencies and is not -j safe. </dev/null guards any stray interactive read.
make </dev/null

# Re-assert the install path in include/rootDir.h and the bin/* helper scripts.
./sbin/setPath "${CALCHEP_HOME}"

# Bundle the numerical static archives into ONE shared library so the package ships
# a shared lib instead of static .a (conda-forge prefers shared). A SINGLE combined
# .so is required: CalcHEP's -fcommon tentative globals (nin_int, nprc_int, ...) are
# shared across these archives and merged at link; separate per-archive .so would
# give each its own copy and break the engine. --whole-archive pulls in every object
# so all symbols are present; symbols provided by n_calchep.o and the per-process
# libs stay undefined and resolve at the run-time n_calchep link (normal for a .so).
# dummy.a (overridable user-function stubs) is intentionally kept static and linked
# last by ld_n. dynamic_vp.a (vp_dynam.o) is likewise kept OUT of the .so: sbin/ld_n
# never links it into n_calchep, and it defines the model tables (nModelParticles,
# ModelPrtcls, varNames, varValues, ...) as -fcommon tentative globals. Those must
# stay UNDEFINED in n_calchep so the run-time-dlopen'd VandP.so supplies the real
# model; folding them into libcalchep.so (loaded NEEDED at startup) would define them
# as zero-filled BSS that shadows VandP.so, so the engine reads an empty particle
# table and segfaults during integration. dynamic_vp.a stays static, linked only by
# bin/make_main (its sole consumer). The .so thus holds exactly the core archives that
# n_calchep already linked statically -- no symbol it did not previously define.
#
# faux.o (the Fortran half of the SLHA bridge: fortranreadline_, cmixmatrix_, ...) is
# linked in because the C half (libSLHAplus's fortran.o, pulled by --whole-archive)
# calls it at run time, so -lgfortran is needed too (libgfortran is already a run dep
# via the Fortran compiler's run-export). The LHAPDF interface (sf_lha.o) keeps its
# undefined libLHAPDF symbols (evolvePDFm, ...): LHAPDF is opt-in, so they resolve
# lazily at run time only when a user supplies LHAPDF -- hence the consumer links use
# -Wl,--allow-shlib-undefined (see install_calchep.sh and patches/0004).
( cd lib && \
  "${CC}" ${CFLAGS:-} -shared -Wl,-soname,libcalchep.so -o libcalchep.so \
    -Wl,--whole-archive \
      num_c.a ntools.a dynamic_me.a libSLHAplus.a serv.a \
    -Wl,--no-whole-archive \
      faux.o -lm -lgfortran )

# The work/bin symlink points at the absolute build-prefix bin/ and would not
# survive relocation; drop it (mkWORKdir recreates a correct one per work dir).
rm -f work/bin
