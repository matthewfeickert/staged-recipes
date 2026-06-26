#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail -o xtrace

# This output inherits the fully built (blind) tree from the staging cache at
# ${PREFIX}/share/calchep. Here we only finalize it: fix the recorded run-time
# compiler, expose the user-facing tools on PATH, and ship activation scripts.
CALCHEP_HOME="${PREFIX}/share/calchep"

# Record portable, bare compiler names for the run-time JIT compilation step.
# The build-time conda compiler (e.g. x86_64-conda-linux-gnu-cc) does not exist
# at run time, and its build-only CFLAGS (sysroot, -fdebug-prefix-map, ...) would
# be wrong there too. Reset to CalcHEP's portable defaults; bare gcc/g++/gfortran
# resolve when the user has the conda-forge gcc/gxx/gfortran packages (or system
# compilers). Generating a new process requires such a compiler in the
# environment (see about.description). -fcommon is kept for the same reason it is
# needed at build time. SNUM/SO/lDL/lFort/lQuad determined by getFlags are left
# untouched so run-time compilation matches the shipped libraries. The
# -Wno-error=* flags keep on-demand process compilation working on the user's
# GCC >= 14 (which errors on the same legacy-C constructs as at build time).
LEGACY_C="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=implicit-int"
sed -i.bak -E \
  -e 's|^CC=.*|CC="gcc"|' \
  -e 's|^CXX=.*|CXX="g++"|' \
  -e 's|^FC=.*|FC="gfortran"|' \
  -e "s|^CFLAGS=.*|CFLAGS=\"-g -fsigned-char -std=gnu99 -fPIC -fcommon ${LEGACY_C}\"|" \
  -e 's|^CXXFLAGS=.*|CXXFLAGS="-g -fPIC -fcommon"|' \
  -e 's|^FFLAGS=.*|FFLAGS="-fno-automatic"|' \
  -e 's|^RANLIB=.*|RANLIB="ranlib"|' \
  "${CALCHEP_HOME}/FlagsForSh"
sed -i.bak -E \
  -e 's|^CC = .*|CC = gcc|' \
  -e 's|^CXX=.*|CXX=g++|' \
  -e 's|^FC = .*|FC = gfortran|' \
  -e "s|^CFLAGS = .*|CFLAGS = -g -fsigned-char -std=gnu99 -fPIC -fcommon ${LEGACY_C}|" \
  -e 's|^CXXFLAGS = .*|CXXFLAGS = -g -fPIC -fcommon|' \
  -e 's|^FFLAGS = .*|FFLAGS = -fno-automatic|' \
  -e 's|^RANLIB = .*|RANLIB = ranlib|' \
  "${CALCHEP_HOME}/FlagsForMake"
rm -f "${CALCHEP_HOME}/FlagsForSh.bak" "${CALCHEP_HOME}/FlagsForMake.bak"

# Expose the user-facing tools via relative (relocatable) symlinks, namespaced
# with a ``calchep-`` prefix to avoid colliding with generic names on PATH
# (e.g. CalcHEP's bare ``calc``/``Int``). Internal JIT helpers (make_main,
# mkLibstat, mkLibshared, subproc_cycle, make_VandP, Int) are intentionally not
# exposed; they remain reachable via ${CALCHEP}/bin.
mkdir -p "${PREFIX}/bin"
ln -s "../share/calchep/mkWORKdir" "${PREFIX}/bin/calchep-mkWORKdir"
for tool in s_calchep event2lhe events2tab lhe2tab event_mixer \
            show_distr sum_distr lhapdf2pdt; do
  ln -s "../share/calchep/bin/${tool}" "${PREFIX}/bin/calchep-${tool}"
done

# Activation scripts (bash/POSIX, csh, fish) export CALCHEP so the engine and
# downstream packages (e.g. micrOMEGAs) can locate the installation, and so the
# binaries that consult getenv("CALCHEP") are robust against any relocation edge
# case.
for stage in activate deactivate; do
  mkdir -p "${PREFIX}/etc/conda/${stage}.d"
  for ext in sh csh fish; do
    cp "${RECIPE_DIR}/${stage}.${ext}" \
       "${PREFIX}/etc/conda/${stage}.d/calchep_${stage}.${ext}"
  done
done
