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
#conan install bzip2_conanfile.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client

# install libxml2 (it fails in Xcode Cloud, so try it second)
#conan install libxml2_conanfile.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client

# install dependencies Release and Debug for macOS and iOS (uncomment for all platforms)
#conan install conanfile.txt --profile conanprofile_macos.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client
#conan install conanfile.txt --profile conanprofile_macos.txt --settings build_type=Debug --build=missing --output-folder=../../opentdf-client
conan install conanfile.txt --profile conanprofile_ios.txt --settings build_type=Release --build=missing --output-folder=../../opentdf-client
conan install conanfile.txt --profile conanprofile_ios.txt --settings build_type=Debug --build=missing --output-folder=../../opentdf-client

# fix for skipped dependencies (TODO figure why and fix)
input_file_path="../../opentdf-client/build/Debug/generators/conan_opentdf_client_libopentdf.xcconfig"
# Create a temporary file that will eventually replace the original file
temp_file=$(mktemp)
# Remove lines containing the specified strings using sed
sed -e '/#include "conan_ms_gsl.xcconfig"/d' -e '/#include "conan_nlohmann_json.xcconfig"/d' -e '/#include "conan_magic_enum.xcconfig"/d' "$input_file_path" > "$temp_file"
# Replace the original file with the modified temporary file
mv "$temp_file" "$input_file_path"
# Give the user read and write permission to the modified original file
chmod 644 "$input_file_path"
