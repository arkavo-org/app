# Arkavo app
_for the Apple ecosystem_

## Development by contributor

### Setup OpenTDF client.

- GitHub source  https://github.com/opentdf/client-cpp
- ConanCenter  https://conan.io/center/recipes/opentdf-client

Run script to download and build dependencies. Also used in Xcode Cloud build.

```shell
cd Arkavo/ci_scripts
./ci_pre_xcodebuild.sh
```

#### Xcode project configuration

- Verify `conan_opentdf_client.xcconfig` as resource from `build/Debug/generators`
- Verify Arkavo project Configurations "Based on Configuration File" to `conan_opentdf_client`

### Command line build

```shell
cd Arkavo
xcodebuild clean build analyze -arch arm64
```

### General process to add C++ library

To include a C++ project within a Swift there are a couple of steps to be performed.

1. Conan build
2. Import .xcconfig
3. Create an .mm and .h file - a wrapper
4. Include the C++ .h in your .mm
5. Create a Bridging-Header, import wrapper header
6. Use the wrapper in your .swift file, no import needed
