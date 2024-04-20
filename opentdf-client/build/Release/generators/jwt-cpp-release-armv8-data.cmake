########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

set(jwt-cpp_COMPONENT_NAMES "")
if(DEFINED jwt-cpp_FIND_DEPENDENCY_NAMES)
  list(APPEND jwt-cpp_FIND_DEPENDENCY_NAMES OpenSSL picojson)
  list(REMOVE_DUPLICATES jwt-cpp_FIND_DEPENDENCY_NAMES)
else()
  set(jwt-cpp_FIND_DEPENDENCY_NAMES OpenSSL picojson)
endif()
set(OpenSSL_FIND_MODE "NO_MODULE")
set(picojson_FIND_MODE "NO_MODULE")

########### VARIABLES #######################################################################
#############################################################################################
set(jwt-cpp_PACKAGE_FOLDER_RELEASE "/Users/paul/.conan2/p/jwt-c7265cc88e98e2/p")
set(jwt-cpp_BUILD_MODULES_PATHS_RELEASE )


set(jwt-cpp_INCLUDE_DIRS_RELEASE )
set(jwt-cpp_RES_DIRS_RELEASE )
set(jwt-cpp_DEFINITIONS_RELEASE )
set(jwt-cpp_SHARED_LINK_FLAGS_RELEASE )
set(jwt-cpp_EXE_LINK_FLAGS_RELEASE )
set(jwt-cpp_OBJECTS_RELEASE )
set(jwt-cpp_COMPILE_DEFINITIONS_RELEASE )
set(jwt-cpp_COMPILE_OPTIONS_C_RELEASE )
set(jwt-cpp_COMPILE_OPTIONS_CXX_RELEASE )
set(jwt-cpp_LIB_DIRS_RELEASE )
set(jwt-cpp_BIN_DIRS_RELEASE )
set(jwt-cpp_LIBRARY_TYPE_RELEASE UNKNOWN)
set(jwt-cpp_IS_HOST_WINDOWS_RELEASE 0)
set(jwt-cpp_LIBS_RELEASE )
set(jwt-cpp_SYSTEM_LIBS_RELEASE )
set(jwt-cpp_FRAMEWORK_DIRS_RELEASE )
set(jwt-cpp_FRAMEWORKS_RELEASE )
set(jwt-cpp_BUILD_DIRS_RELEASE )
set(jwt-cpp_NO_SONAME_MODE_RELEASE FALSE)


# COMPOUND VARIABLES
set(jwt-cpp_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${jwt-cpp_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${jwt-cpp_COMPILE_OPTIONS_C_RELEASE}>")
set(jwt-cpp_LINKER_FLAGS_RELEASE
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${jwt-cpp_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${jwt-cpp_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${jwt-cpp_EXE_LINK_FLAGS_RELEASE}>")


set(jwt-cpp_COMPONENTS_RELEASE )