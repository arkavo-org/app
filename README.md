# app
Arkavo app for the Apple ecosystem

## Development

Conan build the OpenTDF client-cpp

```shell
conan install . -s build_type=Debug --build=all -g=XcodeDeps
```

Add `conan_opentdf_client_libopentdf.xcconfig` from `build/Debug/generators`
