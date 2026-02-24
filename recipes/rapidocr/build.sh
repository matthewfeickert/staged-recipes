#!/bin/bash
set -euxo pipefail

cd python

# The setup.py dynamically computes the version by importing
# get_pypi_latest_version and querying PyPI. This package is not on
# conda-forge and the behaviour is undesirable for reproducible builds.
# Patch setup.py to use a static version instead.
python -c "
import re

with open('setup.py') as f:
    s = f.read()

# Remove the import
s = s.replace('from get_pypi_latest_version import GetPyPiLatestVersion', '')

# Replace the version computation block with a static version
s = re.sub(
    r'obtainer = GetPyPiLatestVersion\(\).*?sys\.argv = sys\.argv\[:2\]',
    'VERSION_NUM = \"${PKG_VERSION}\"',
    s,
    flags=re.DOTALL,
)

with open('setup.py', 'w') as f:
    f.write(s)
"

$PYTHON -m pip install . -vv --no-deps --no-build-isolation
