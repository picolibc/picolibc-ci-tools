#!/bin/sh
#
# Run in arm-toolchain/arm-software/embedded/build
#
# Then run
#  $ ninja llvm-toolchain
#
# To package
#  $ ninja package-llvm-toolchain
#
HERE="$(dirname "$0")"
TOP="$HERE/.."
export CC=clang
export CXX=clang++
cmake "$TOP"/arm-toolchain/arm-software/embedded -GNinja -DFETCHCONTENT_QUIET=OFF || exit 1
ninja llvm-toolchain || exit 1
ninja package-llvm-toolchain || exit 1
mv ATfE-23.0.0-pre-*.tar.xz "$TOP"
