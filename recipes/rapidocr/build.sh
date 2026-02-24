#!/bin/bash
set -euxo pipefail

cd python

# The setup.py has two issues that prevent a clean conda build:
#
# 1. It dynamically computes the version by importing get_pypi_latest_version
#    (not on conda-forge) and querying PyPI. We replace this with a static version.
#
# 2. It uses package_dir={"": "rapidocr"} with find_namespace_packages(where="rapidocr"),
#    which installs subpackages (ch_ppocr_det, inference_engine, etc.) as top-level
#    packages instead of under the "rapidocr" namespace. The PyPI wheel is built
#    differently and has the correct layout. We fix this by using find_packages()
#    with default package_dir.
python -c "
import re

with open('setup.py') as f:
    s = f.read()

# Remove the get_pypi_latest_version import
s = s.replace('from get_pypi_latest_version import GetPyPiLatestVersion', '')

# Replace the version computation block with a static version
s = re.sub(
    r'obtainer = GetPyPiLatestVersion\(\).*?sys\.argv = sys\.argv\[:2\]',
    'VERSION_NUM = \"${PKG_VERSION}\"',
    s,
    flags=re.DOTALL,
)

# Fix package discovery: use find_packages() so that 'rapidocr' is the
# top-level package with all subpackages nested correctly.
s = s.replace(
    'package_dir={\"\": MODULE_NAME},',
    ''
)
s = s.replace(
    'packages=setuptools.find_namespace_packages(where=MODULE_NAME),',
    'packages=setuptools.find_packages(exclude=[\"tests\", \"tests.*\"]),',
)

with open('setup.py', 'w') as f:
    f.write(s)
"

$PYTHON -m pip install . -vv --no-deps --no-build-isolation
