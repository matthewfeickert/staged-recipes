#!/bin/bash

export FOAM_DIR_NAME="${SRC_DIR}" #/openfoam-OpenFOAM-${PKG_VERSION}"

# source foam dot file throws error if not compiled
# modify the the output folder of the binaries 
sed -i 's/\$WM_PROJECT_DIR\/platforms\/\$WM_OPTIONS/\$\{PREFIX\}/g' ${FOAM_DIR_NAME}/etc/config.sh/settings
source "${FOAM_DIR_NAME}/etc/bashrc" || true
export CONFIGSHDIR=${FOAM_DIR_NAME}/etc/config.sh

# change scotch version to the conda version
sed -i 's/^SCOTCH_VERSION=.*/SCOTCH_VERSION=scotch-system/g' ${CONFIGSHDIR}/scotch
sed -i 's/^export SCOTCH_ARCH_PATH=.*/export SCOTCH_ARCH_PATH=${PREFIX}/g' ${CONFIGSHDIR}/scotch

# change kahip version to the conda version
sed -i 's/^KAHIP_VERSION=.*/KAHIP_VERSION=kahip-system/g' ${CONFIGSHDIR}/kahip
sed -i 's/^export KAHIP_ARCH_PATH=.*/export KAHIP_ARCH_PATH=${PREFIX}/g' ${CONFIGSHDIR}/kahip

# change metis version to the conda version
sed -i 's/^METIS_VERSION=.*/METIS_VERSION=metis-system/g' ${CONFIGSHDIR}/metis
sed -i 's/^export METIS_ARCH_PATH=.*/export METIS_ARCH_PATH=${PREFIX}/g' ${CONFIGSHDIR}/metis

# change petsc version to the conda version
sed -i 's/^petsc_version=.*/petsc_version=petsc-system/g' ${CONFIGSHDIR}/petsc
sed -i 's/^export PETSC_ARCH_PATH=.*/export PETSC_ARCH_PATH=${PREFIX}/g' ${CONFIGSHDIR}/petsc

# change hypre version to the conda version
sed -i 's/^hypre_version=.*/hypre_version=hypre-system/g' ${CONFIGSHDIR}/hypre
sed -i 's/^export HYPRE_ARCH_PATH=.*/export HYPRE_ARCH_PATH=${PREFIX}/g' ${CONFIGSHDIR}/hypre
#
echo "cFLAGS += -I ${BUILD_PREFIX}/include" >> "${FOAM_DIR_NAME}/wmake/rules/linux64Gcc/c"
echo "c++FLAGS += -I ${BUILD_PREFIX}/include" >> "${FOAM_DIR_NAME}/wmake/rules/linux64Gcc/c++"

# remove Allwmake falsely sets the headers to the system
rm "${FOAM_DIR_NAME}/applications/utilities/mesh/manipulation/setSet/Allwmake"

#   compile openfoam
${FOAM_DIR_NAME}/Allwmake -j $CPU_COUNT -q -l

#   install
echo "Installing ..."

cd ${FOAM_DIR_NAME}
# transportProperties are not referenced via
mkdir -p  ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/src/
cp -Lr src/transportModels ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/src/

#copy header in the include folder
for f in $(find . -type d -name lnInclude)
do
    if [ ! -d "$(dirname ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/${f})" ]; then
        mkdir -p  $(dirname ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/${f})
    fi
    cp -Lr ${f} $(dirname ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/${f})
done

# copy wmake and modify wmake scripts
SCRIPTDIR="\${0%\/\*}"
NEW_SCRIPTDIR="\${WM_PROJECT_DIR:\?}\/wmake"
sed -i "s/$SCRIPTDIR/$NEW_SCRIPTDIR/g" wmake/w*
cp wmake/w* ${PREFIX}/bin

# copy config and script files
cp -r etc ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/ 
cp -r bin ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/
cp -r wmake ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/
cp -r platforms ${PREFIX}/include/OpenFOAM-${PKG_VERSION}/

ACTIVATE_DIR="${PREFIX}/etc/conda/activate.d"
DEACTIVATE_DIR="${PREFIX}/etc/conda/deactivate.d"

mkdir -p "${ACTIVATE_DIR}"
mkdir -p "${DEACTIVATE_DIR}"

cp "${RECIPE_DIR}/activate.sh" "${ACTIVATE_DIR}/openfoam-activate.sh"
cp "${RECIPE_DIR}/deactivate.sh" "${DEACTIVATE_DIR}/openfoam-deactivate.sh"
