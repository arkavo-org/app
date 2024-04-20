#!/bin/sh

# Set the -e flag to stop running the script in case a command returns
# a nonzero exit code.
set -e

# install conan
/usr/bin/python3 -m pip install conan

# install dependencies
conan install conanfile.txt --build=missing -g=XcodeDeps
