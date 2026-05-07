#!/usr/bin/env bash
set -euxo pipefail

# GX has no tagged releases; this recipe builds from a pinned commit on the
# 'gx' branch. The upstream Makefile expects a system-specific
# Makefiles/Makefile.<GK_SYSTEM>; we generate one tailored for the
# conda-forge build environment, then invoke `make`.

# Multi-architecture CUDA build: target the major architectures supported by
# CUDA 12. `-arch=all-major` would also work on CUDA >= 11.5, but listing
# arches explicitly keeps the targets visible and reproducible.
GENCODE_FLAGS="\
  -gencode=arch=compute_70,code=sm_70 \
  -gencode=arch=compute_75,code=sm_75 \
  -gencode=arch=compute_80,code=sm_80 \
  -gencode=arch=compute_86,code=sm_86 \
  -gencode=arch=compute_89,code=sm_89 \
  -gencode=arch=compute_90,code=sm_90 \
  -gencode=arch=compute_90,code=compute_90"

cat > Makefiles/Makefile.condaforge <<EOF
# conda-forge configuration for GX
# CUDA toolkit, MPI, NetCDF, HDF5, and GSL are all provided by the host env.

NETCDF_INC = -I \${PREFIX}/include
NETCDF_LIB = -L \${PREFIX}/lib -lnetcdf -lnetcdff -lhdf5

MPI_INC = -I \${PREFIX}/include
MPI_LIB = -L \${PREFIX}/lib -lmpi

# CUDA libraries: cudart, NCCL, cuFFT (static), cuBLAS, cuSOLVER, cuTENSOR,
# cuLIBOS (static, shipped in cuda-cudart-static). -lgomp pulls in the GNU
# OpenMP runtime that some CUDA static libs reference.
#
# conda-forge's CUDA static libraries (libcufft_static.a, etc.) are installed
# only under \${PREFIX}/targets/x86_64-linux/lib, not the top-level
# \${PREFIX}/lib, so that path must be added explicitly.
#
# Upstream Makefiles also link -lnvToolsExt, but no GX source references any
# NVTX symbols and CUDA 12 ships only the header-only NVTX3 API on
# conda-forge (no libnvToolsExt.so), so the flag is dropped.
CUDA_INC = -I \${PREFIX}/include
CUDA_LIB = -L \${PREFIX}/lib -L \${PREFIX}/targets/x86_64-linux/lib -lcufft_static -lcublas -lcusolver -lgomp -lcutensor -lnccl -lcudart -lculibos

GSL_INC = -I \${PREFIX}/include
GSL_LIB = -L \${PREFIX}/lib -lgsl -lgslcblas

C_LIB = -lm -lpthread -ldl

# Resolve \${CXX} and \${GENCODE_FLAGS} now (in the shell) so make sees a
# literal compiler path. Leaving \${CXX} unexpanded would yield a recursive
# self-reference (CXX = \${CXX}) when make evaluates the variable.
CXX = ${CXX}
NVCC = nvcc
CFLAGS = -fPIC -O3
NVCCFLAGS = --forward-unknown-to-host-compiler -ccbin=${CXX} ${GENCODE_FLAGS} -use_fast_math -fPIC -rdc=true -O3
EOF

export GK_SYSTEM=condaforge

# obj/geo/ must exist before make tries to populate it.
mkdir -p obj/geo

make --jobs="${CPU_COUNT}" gx

mkdir -p "${PREFIX}/bin"
install -m 0755 gx "${PREFIX}/bin/gx"
