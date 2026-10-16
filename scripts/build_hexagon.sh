#!/bin/sh

TOP="$(dirname "$0")/.."
HERE=`pwd`

LLVM_REVISION=821624a42136c1b0c6b18962540eb57fa68937e8
ELD_REVISION=c32706435330e1023fef0e2e047ca456ff696827
TRIPLE=hexagon-unknown-none-elf
TARGET=Hexagon
ARCH=hexagon
INSTALL=${HERE}/clang-${ARCH}-toolchain
BUILD=${HERE}/build-${ARCH}-toolchain
BUILTINS_BUILD=${HERE}/build-${ARCH}-builtins
BUILTINS_INSTALL=${INSTALL}/target/picolibc/${TRIPLE}/lib
PLATFORM=$(uname -sm | tr ' ' '-')
MAX_SIZE=$((2 * 1024 * 1024 * 1024))  # 2 GB in bytes
OUTPUT="${TOP}/$(basename ${INSTALL}).${PLATFORM}.tar.xz"

case "$TOP" in
    /*)
	;;
    *)
	TOP="$(pwd)/$TOP"
	;;
esac

PATH=$TOP/.local/bin:$PATH
if [ ! -d llvm-project ]; then
    echo "Cloning LLVM"
    git clone --revision $LLVM_REVISION --depth 1 https://github.com/llvm/llvm-project llvm-project || exit 1
fi
if [ ! -d llvm-project/llvm/tools/eld ]; then
    echo "Cloning tools/eld"
    git clone --revision $ELD_REVISION --depth 1 https://github.com/qualcomm/eld llvm-project/llvm/tools/eld || exit 1
fi    
echo "Configure LLVM"
set -x
cmake -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_PROJECTS="llvm;clang" \
      -DLLVM_DEFAULT_TARGET_TRIPLE=${TRIPLE} \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_CXX_FLAGS="-stdlib=libc++" \
      -DLLVM_TARGETS_TO_BUILD=${TARGET} \
      -DELD_TARGETS_TO_BUILD=${TARGET} \
      -DCMAKE_INSTALL_PREFIX=${INSTALL} \
      -S ${HERE}/llvm-project/llvm \
      -B ${BUILD} || exit 1
set +x
echo "Build and install LLVM"
cmake --build ${HERE}/build-${ARCH}-toolchain -- install  || exit 1

build_builtins()
{
    name=$1
    pic=$2
    flags=$3
    build=${BUILTINS_BUILD}/${name}
    install=${BUILTINS_INSTALL}/${name}

    echo "Configure compiler-rt builtins for ${name}"
    set -x
    cmake -G Ninja \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_C_COMPILER=${BUILD}/bin/clang \
          -DCMAKE_CXX_COMPILER=${BUILD}/bin/clang++ \
          -DCMAKE_C_COMPILER_WORKS=ON \
          -DCMAKE_CXX_COMPILER_WORKS=ON \
          -DCMAKE_C_COMPILER_TARGET=${TRIPLE} \
          -DCMAKE_CXX_COMPILER_TARGET=${TRIPLE} \
          -DCMAKE_C_FLAGS="${flags}" \
          -DCMAKE_CXX_FLAGS="${flags}" \
          -DCMAKE_INSTALL_PREFIX=${INSTALL} \
          -DCOMPILER_RT_INSTALL_LIBRARY_DIR=${install} \
          -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
          -DLLVM_CMAKE_DIR=${BUILD}/lib/cmake/llvm \
          -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
          -DCOMPILER_RT_BUILD_BUILTINS=ON \
          -DCOMPILER_RT_BUILTINS_ENABLE_PIC=${pic} \
          -DCOMPILER_RT_BAREMETAL_BUILD=ON \
          -DCOMPILER_RT_BUILD_CRT=OFF \
          -DCOMPILER_RT_INCLUDE_TESTS=OFF \
          -DCMAKE_SYSTEM_NAME="Generic" \
          -S ${HERE}/llvm-project/compiler-rt \
          -B ${build} || exit 1
    cmake --build ${build} --target install || exit 1
    test -f "${install}/libclang_rt.builtins-hexagon.a" || exit 1
    mv "${install}/libclang_rt.builtins-hexagon.a" \
       "${install}/libclang_rt.builtins.a" || exit 1
    set +x
}

build_builtins v68 OFF "-ffreestanding"
build_builtins v68-G0 OFF "-G0 -ffreestanding"
build_builtins v68-G0-pic ON "-G0 -fPIC -ffreestanding"

echo "Pack toolchain install"
tar -C $(dirname ${INSTALL}) -cJf "${OUTPUT}" $(basename ${INSTALL})
ACTUAL_SIZE=$(stat -c %s "${OUTPUT}")
echo "Size of ${OUTPUT}: ${ACTUAL_SIZE}. Limit: ${MAX_SIZE}."
if [ "${ACTUAL_SIZE}" -gt "${MAX_SIZE}" ]; then
    echo "${OUTPUT}: ${ACTUAL_SIZE} exceeds ${MAX_SIZE} limit"
    exit 1
fi
exit 0
