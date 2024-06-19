#!/bin/bash

export ROOT=$(dirname $(readlink -f ${0}))

set -e # exit on first error

function check_available_memory_and_disk() {
    FREE_MEM_GB=$(free -g -t | grep 'Mem' | rev | cut -d" " -f1 | rev)
    MIN_MEM_GB=10

    FREE_DISK_KB=$(df -k . | tail -1 | awk '{print $4}')
    MIN_DISK_KB=$((10 * 1024 * 1024))

    if [ ${FREE_MEM_GB} -le ${MIN_MEM_GB} ]; then
        echo -e "\nERROR: Orca Slicer Builder requires at least ${MIN_MEM_GB}G of 'available' mem (systen has only ${FREE_MEM_GB}G available)"
        echo && free -h && echo
        exit 2
    fi

    if [[ ${FREE_DISK_KB} -le ${MIN_DISK_KB} ]]; then
        echo -e "\nERROR: Orca Slicer Builder requires at least $(echo ${MIN_DISK_KB} |awk '{ printf "%.1fG\n", $1/1024/1024; }') (systen has only $(echo ${FREE_DISK_KB} | awk '{ printf "%.1fG\n", $1/1024/1024; }') disk free)"
        echo && df -h . && echo
        exit 1
    fi
}

function usage() {
    echo "Usage: ./BuildLinux.sh [-1][-b][-c][-d][-i][-r][-s][-u]"
    echo "   -1: limit builds to 1 core (where possible)"
    echo "   -b: build in debug mode"
    echo "   -c: force a clean build"
    echo "   -d: build deps (optional)"
    echo "   -h: this help output"
    echo "   -i: Generate appimage (optional)"
    echo "   -r: skip ram and disk checks (low ram compiling)"
    echo "   -s: build orca-slicer (optional)"
    echo "   -u: update and build dependencies (optional and need sudo)"
    echo "For a first use, you want to 'sudo ./BuildLinux.sh -u'"
    echo "   and then './BuildLinux.sh -dsi'"
}


function build_deps() {
    echo "Configuring dependencies..."
    type=$1
    BUILD_ARGS="-DDEP_WX_GTK3=ON"
    if [[ -n "${type}" ]]
    then
        BUILD_ARGS="${BUILD_ARGS} -DCMAKE_BUILD_TYPE=Debug"
    else
        BUILD_ARGS="${BUILD_ARGS} -DCMAKE_BUILD_TYPE=RelWithDebInfo"
    fi

    echo "cmake -S ${ROOT}/deps -B ${ROOT}/deps/build -DDESTDIR="${ROOT}/deps/destdir" ${BUILD_ARGS}"
    cmake -S ${ROOT}/deps -B ${ROOT}/deps/build -DDESTDIR="${ROOT}/deps/destdir" ${BUILD_ARGS}
    cmake --build ${ROOT}/deps/build
}

function build_application() {
    BUILD_ARGS=""
    if [[ -n "${FOUND_GTK3_DEV}" ]]
    then
        BUILD_ARGS="-DSLIC3R_GTK=3"
    fi
    BuildConfig="RelWithDebInfo"
    if [[ -n "${BUILD_DEBUG}" ]]
    then
        BuildConfig="Debug"
        BUILD_ARGS="${BUILD_ARGS} -DCMAKE_BUILD_TYPE=Debug -DBBL_INTERNAL_TESTING=1"
    else
        BUILD_ARGS="${BUILD_ARGS} -DBBL_RELEASE_TO_PUBLIC=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBBL_INTERNAL_TESTING=0"
    fi
    echo -e "cmake -S ${ROOT} -B ${ROOT}/build -DCMAKE_PREFIX_PATH="${ROOT}/deps/destdir/usr/local" -DSLIC3R_STATIC=1 ${BUILD_ARGS}"
    cmake -S ${ROOT} -B ${ROOT}/build \
        -DCMAKE_PREFIX_PATH="${ROOT}/deps/destdir/usr/local" \
        -DSLIC3R_STATIC=1 \
        -DORCA_TOOLS=ON \
        ${BUILD_ARGS}
    echo "done"
    echo "Building OrcaSlicer ..."
    echo "cmake --build build --config ${BuildConfig} -j`cat /proc/cpuinfo |grep processor|wc -l`"
    cmake --build build --config ${BuildConfig} -j`cat /proc/cpuinfo |grep processor|wc -l`
    /bin/bash ${ROOT}/run_gettext.sh
}

function build_image(){
    echo "[9/9] Generating Linux app..."
    image=$1
        pushd build
            if [[ -n "${image}" ]]
            then
                /bin/bash ${ROOT}/build/src/BuildLinuxImage.sh -i
            else
                /bin/bash ${ROOT}/build/src/BuildLinuxImage.sh
            fi
        popd
    echo "done"
}

unset name
while getopts ":1bcdghirsu" opt; do
  case ${opt} in
    1 )
        export CMAKE_BUILD_PARALLEL_LEVEL=1
        ;;
    b )
        BUILD_DEBUG="1"
        ;;
    c )
        CLEAN_BUILD=1
        ;;
    d )
        BUILD_DEPS="1"
        ;;
    h ) usage
        exit 0
        ;;
    i )
        BUILD_IMAGE="1"
        ;;
    r )
	    SKIP_RAM_CHECK="1"
	;;
    s )
        BUILD_ORCA="1"
        ;;
    u )
        UPDATE_LIB="1"
        ;;
  esac
done

if [ ${OPTIND} -eq 1 ]
then
    usage
    exit 0
fi

DISTRIBUTION=$(awk -F= '/^ID=/ {print $2}' /etc/os-release)
# treat ubuntu as debian
if [ "${DISTRIBUTION}" == "ubuntu"  -o "${DISTRIBUTION}" == "Deepin" ]
then
    DISTRIBUTION="debian"
fi
if [ ! -f ./linux.d/${DISTRIBUTION} ]
then
    echo "Your distribution does not appear to be currently supported by these build scripts"
    exit 1
fi
source ./linux.d/${DISTRIBUTION}

echo "FOUND_GTK3=${FOUND_GTK3}"
if [[ -z "${FOUND_GTK3_DEV}" ]]
then
    echo "Error, you must install the dependencies before."
    echo "Use option -u with sudo"
    exit 1
fi

echo "Changing date in version..."
{
    # change date in version
    sed -i "s/+UNKNOWN/_$(date '+%F')/" version.inc
}
echo "done"


if ! [[ -n "${SKIP_RAM_CHECK}" ]]
then
    check_available_memory_and_disk
fi

if [[ -n "${BUILD_DEPS}" ]]
then
    echo "Configuring dependencies..."
    if [[ -n "${CLEAN_BUILD}" ]]
    then
        rm -fr ${ROOT}/deps/build
    fi
    build_deps ${BUILD_DEBUG}
    echo "done"
fi


if [[ -n "${BUILD_ORCA}" ]]
then
    echo "Configuring OrcaSlicer..."
    if [[ -n "${CLEAN_BUILD}" ]]
    then
        rm -fr ${ROOT}/build
    fi
    build_application ${BUILD_DEBUG}
    echo "done"
fi

if [[ -e ${ROOT}/build/src/BuildLinuxImage.sh ]]; then
    build_image ${BUILD_IMAGE}
    echo "done"
fi
