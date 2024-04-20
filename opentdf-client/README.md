# OpenTDF C++ client

- Github source  https://github.com/opentdf/client-cpp
- ConanCenter  https://conan.io/center/recipes/opentdf-client

## Overview

To include a C++ project within a Swift there are a couple of steps to be performed.

1. Conan build
2. Import .xcconfig
3. Create an .mm and .h file - a wrapper
4. Include the C++ .h in your .mm
5. Create a Bridging-Header, import wrapper header
6. Use the wrapper in your .swift file, no import needed

## Setup

Conan build the OpenTDF C++ client

```shell
conan install conanfile.txt --build=missing -g=XcodeDeps
```

Add `conan_opentdf_client.xcconfig` from `build/Debug/generators`

## CI - Xcode Cloud

