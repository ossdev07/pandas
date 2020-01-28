#!/bin/bash -e
IS_SUDO="sudo"
ARCHICONDA_PYTHON="python3.7"
echo `which python`
# edit the locale file if needed
if [[ "$(uname)" == "Linux" && -n "$LC_ALL" ]]; then
    echo "Adding locale to the first line of pandas/__init__.py"
    rm -f pandas/__init__.pyc
    SEDC="3iimport locale\nlocale.setlocale(locale.LC_ALL, '$LC_ALL')\n"
    sed -i "$SEDC" pandas/__init__.py

    echo "[head -4 pandas/__init__.py]"
    head -4 pandas/__init__.py
    echo
fi

MINICONDA_DIR="$HOME/archiconda3"


if [ -d "$MINICONDA_DIR" ]; then
    echo
    echo "rm -rf "$MINICONDA_DIR""
    rm -rf "$MINICONDA_DIR"
fi

echo "Install Miniconda"
UNAME_OS=$(uname)

wget -q "https://github.com/Archiconda/build-tools/releases/download/0.2.3/Archiconda3-0.2.3-Linux-aarch64.sh" -O archiconda.sh
chmod +x archiconda.sh
./archiconda.sh -b 
echo "chmod MINICONDA_DIR"
$IS_SUDO chmod -R 777 $MINICONDA_DIR
$IS_SUDO cp $MINICONDA_DIR/bin/* /usr/bin/
$IS_SUDO cp $MINICONDA_DIR/lib/libpython* /usr/lib/
$IS_SUDO rm /usr/bin/lsb_release
export PATH=/usr/bin:$MINICONDA_DIR/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:/usr/local/bin/python:$LD_LIBRARY_PATH

echo
echo "which conda"
which conda

echo
echo "update conda"
conda config --set ssl_verify false
conda config --set quiet true --set always_yes true --set changeps1 false
$IS_SUDO conda install pip  # create conda to create a historical artifact for pip & setuptools
$IS_SUDO conda update -n base conda

echo "conda info -a"
conda info -a

echo
echo "set the compiler cache to work"
if [ -z "$NOCACHE" ] && [ "${TRAVIS_OS_NAME}" == "linux" ]; then
    echo "Using ccache"
    export PATH=/usr/lib/ccache:/usr/lib64/ccache:$PATH
    GCC=$(which gcc)
    echo "gcc: $GCC"
    CCACHE=$(which ccache)
    echo "ccache: $CCACHE"
    export CC='ccache gcc'
elif [ -z "$NOCACHE" ] && [ "${TRAVIS_OS_NAME}" == "osx" ]; then
    echo "Install ccache"
    brew install ccache > /dev/null 2>&1
    echo "Using ccache"
    export PATH=/usr/local/opt/ccache/libexec:$PATH
    gcc=$(which gcc)
    echo "gcc: $gcc"
    CCACHE=$(which ccache)
    echo "ccache: $CCACHE"
else
    echo "Not using ccache"
fi

echo "source deactivate"
source deactivate

echo "conda list (root environment)"
conda list

# Clean up any left-over from a previous build
# (note workaround for https://github.com/conda/conda/issues/2679:
#  `conda env remove` issue)
conda remove --all -q -y -n pandas-dev

echo
$IS_SUDO chmod -R 777 $MINICONDA_DIR
$IS_SUDO apt-get install xvfb
$IS_SUDO conda install botocore
$IS_SUDO conda install python-dateutil=2.8.0
$IS_SUDO conda install pytz
$IS_SUDO chmod -R 777 $MINICONDA_DIR

echo "conda env create -q --file=${ENV_FILE}"
time $IS_SUDO conda env create -q --file="${ENV_FILE}"


if [[ "$BITS32" == "yes" ]]; then
    # activate 32-bit compiler
    export CONDA_BUILD=1
fi

echo "activate pandas-dev"
source activate pandas-dev

echo
echo "remove any installed pandas package"
echo "w/o removing anything else"
$IS_SUDO conda remove pandas -y --force || true
pip uninstall -y pandas || true

echo
echo "remove postgres if has been installed with conda"
echo "we use the one from the CI"
$IS_SUDO conda remove postgresql -y --force || true

echo
echo "conda list pandas"
conda list pandas

# Make sure any error below is reported as such

echo "[Build extensions]"
sudo chmod -R 777 /home/travis/.ccache
python setup.py build_ext -q -i

# XXX: Some of our environments end up with old versions of pip (10.x)
# Adding a new enough version of pip to the requirements explodes the
# solve time. Just using pip to update itself.
# - py35_macos
# - py35_compat
# - py36_32bit
echo "[Updating pip]"
sudo chmod -R 777 /home/travis/archiconda3/envs/pandas-dev/lib/$ARCHICONDA_PYTHON/site-packages
#$IS_SUDO $ARCHICONDA_PYTHON -m pip install pytest-forked
#$IS_SUDO $ARCHICONDA_PYTHON -m pip install pytest-xdist
pip install --no-deps -U pip wheel setuptools pytest
sudo chmod -R 777 $MINICONDA_DIR

echo "[Install pandas]"
$IS_SUDO chmod -R 777 $MINICONDA_DIR
pip install numpy hypothesis cython
$IS_SUDO chmod -R 777 /home/travis/.cache/
pip install --no-build-isolation -e .

echo
echo "conda list"
conda list

# Install DB for Linux
if [[ -n ${SQL:0} ]]; then
  echo "installing dbs"
  sudo systemctl start mysql
  mysql -e 'create database pandas_nosetest;'
else
   echo "not using dbs on non-linux Travis builds or Azure Pipelines"
fi

echo "done"
