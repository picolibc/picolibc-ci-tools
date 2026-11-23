#!/bin/sh

TOP="$(dirname "$0")/.."
HERE=`pwd`

LLVM_VERSION=22.1.8 # In Debian 13's stable repo
TRIPLE=loongarch64-unknown-elf
TARGET=loongarch64
ARCH=loongarch64
INSTALL=${HERE}/clang-${ARCH}-toolchain
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

PATH=/usr/lib/llvm-22/bin:$TOP/.local/bin:$PATH # Use system's clang-22
if [ ! -d llvm-project ]; then
    set -e
    echo "Getting LLVM"
    curl -L -O https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz
    tar -xf llvm-project-${LLVM_VERSION}.src.tar.xz
    mv llvm-project-${LLVM_VERSION}.src llvm-project
fi
echo "Configure compiler-rt builtins"
set -x
cmake -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_C_COMPILER_TARGET=${TRIPLE} \
      "-DCMAKE_C_FLAGS= -ffreestanding -fno-stack-protector -Xclang -nostdsysteminc" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      -DCOMPILER_RT_BAREMETAL_BUILD=ON \
      -DCOMPILER_RT_OS_DIR="baremetal" \
      -DCOMPILER_RT_BUILD_BUILTINS=ON \
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DCOMPILER_RT_BUILD_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_BUILD_ORC=OFF \
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DCOMPILER_RT_INCLUDE_TESTS=OFF \
      -S ${HERE}/llvm-project/compiler-rt \
      -B ${BUILTINS_BUILD} || exit 1
echo "Build compiler-rt"
cmake --build ${BUILTINS_BUILD} || exit 1

mkdir -p "${BUILTINS_INSTALL}" || exit 1
cp "${BUILTINS_BUILD}/lib/baremetal/libclang_rt.builtins-${ARCH}.a" \
   "${BUILTINS_INSTALL}/libclang_rt.builtins.a" || exit 1
set +x

echo "Pack toolchain install"
tar -C $(dirname ${INSTALL}) -cJf "${OUTPUT}" $(basename ${INSTALL})
ACTUAL_SIZE=$(stat -c %s "${OUTPUT}")
echo "Size of ${OUTPUT}: ${ACTUAL_SIZE}. Limit: ${MAX_SIZE}."
if [ "${ACTUAL_SIZE}" -gt "${MAX_SIZE}" ]; then
    echo "${OUTPUT}: ${ACTUAL_SIZE} exceeds ${MAX_SIZE} limit"
    exit 1
fi
exit 0
