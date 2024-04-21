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
#conan profile detect --force

# install bzip2 (it fails in Xcode Cloud, so try it first)
#conan install bzip2_conanfile.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client

# install libxml2 (it fails in Xcode Cloud, so try it second)
#conan install libxml2_conanfile.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client

# install dependencies Release and Debug for macOS and iOS
#conan install conanfile.txt --profile conanprofile_macos.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client
#conan install conanfile.txt --profile conanprofile_macos.txt --settings build_type=Debug --build=missing --output-folder=../../opentdf-client
conan install conanfile.txt --profile conanprofile_ios.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client
conan install conanfile.txt --profile conanprofile_ios.txt --settings build_type=Debug --build=missing --output-folder=../../opentdf-client
