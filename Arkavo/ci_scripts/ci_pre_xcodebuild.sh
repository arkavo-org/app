#!/bin/sh

# Set the -e flag to stop running the script in case a command returns
# a nonzero exit code.
set -e

# install conan
brew install --quiet conan

# conan profile
conan profile detect

# install dependencies
conan install conanfile.txt --build=missing -g=XcodeDeps
