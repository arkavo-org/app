#!/bin/sh

# Set the -e flag to stop running the script in case a command returns
# a nonzero exit code.
set -e

# install conan
brew install --quiet conan
conan version

# conan profile
conan profile detect

# install bzip2 (it fails in Xcode Cloud, so try it first)
conan install bzip2_conanfile.txt --build=missing -g=XcodeDeps

# install dependencies
conan install conanfile.txt --build=missing -g=XcodeDeps
