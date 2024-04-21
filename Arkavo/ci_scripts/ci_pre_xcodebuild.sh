#!/bin/sh

# Set the -e flag to stop running the script in case a command returns
# a nonzero exit code.
set -e

# install conan
export HOMEBREW_NO_INSTALL_CLEANUP=true
export HOMEBREW_NO_ENV_HINTS=true
brew install --quiet conan cmake
conan version

# conan profile
conan profile detect --force

# install bzip2 (it fails in Xcode Cloud, so try it first)
curl -I https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
conan install bzip2_conanfile.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client

# install dependencies
conan install conanfile.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client
