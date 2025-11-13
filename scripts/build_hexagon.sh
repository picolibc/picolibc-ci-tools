#!/bin/sh

TOP="$(dirname "$0")/.."
HERE=`pwd`

LLVM_REVISION=b8868c16f07de8e926d5e564444c49cae651c80d
ELD_REVISION=5d04379a7e32afce6224ebffb2e999447afcab14
TRIPLE=hexagon-unknown-none-elf
TARGET=Hexagon
ARCH=hexagon
INSTALL=${HERE}/clang-${ARCH}-toolchain
BUILD=${HERE}/build-${ARCH}-toolchain
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
echo "Build and install LLVM"
cmake --build ${HERE}/build-${ARCH}-toolchain -- install  || exit 1
echo "Configure compiler-rt builtins"
cmake -G Ninja \
      -DCMAKE_C_COMPILER:STRING=${INSTALL}/bin/clang \
      -DCMAKE_CXX_COMPILER:STRING=${INSTALL}/bin/clang++ \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_CMAKE_DIR:PATH=${INSTALL} \
      -DCMAKE_INSTALL_PREFIX:PATH=$(${INSTALL}/bin/clang -print-resource-dir) \
      -DCMAKE_ASM_FLAGS="-G0 -mlong-calls -fno-pic" \
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
      -DLLVM_TARGET_TRIPLE=${TRIPLE} \
      -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=${TRIPLE} \
      -DCOMPILER_RT_BUILD_BUILTINS=ON \
      -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DCOMPILER_RT_BUILD_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_BUILD_ORC=OFF \
      -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
      -DCOMPILER_RT_BUILTINS_ENABLE_PIC=OFF \
      -DCOMPILER_RT_SUPPORTED_ARCH=${ARCH} \
      -DCOMPILER_RT_BAREMETAL_BUILD=ON \
      -DCMAKE_C_FLAGS="-ffreestanding" \
      -DCMAKE_CXX_FLAGS="-ffreestanding" \
      -DCMAKE_CROSSCOMPILING=ON \
      -DCAN_TARGET_hexagon=1 \
      -DCMAKE_C_COMPILER_FORCED=ON \
      -DCMAKE_CXX_COMPILER_FORCED=ON \
      -DCMAKE_C_COMPILER_TARGET=${TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TRIPLE} \
      -B build-${ARCH}-builtins/ \
      -S ${HERE}/llvm-project/compiler-rt/ || exit 1
echo "Build compiler-rt builtins"
cmake --build ${HERE}/build-${ARCH}-builtins -- install-builtins  || exit 1
echo "Pack toolchain install"
tar -C $(dirname ${INSTALL}) -cJf "${OUTPUT}" $(basename ${INSTALL})
ACTUAL_SIZE=$(stat -c %s "${OUTPUT}")
echo "Size of ${OUTPUT}: ${ACTUAL_SIZE}. Limit: ${MAX_SIZE}."
if [ "${ACTUAL_SIZE}" -gt "${MAX_SIZE}" ]; then
    echo "${OUTPUT}: ${ACTUAL_SIZE} exceeds ${MAX_SIZE} limit"
    exit 1
fi
exit 0
