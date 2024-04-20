########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

set(picojson_COMPONENT_NAMES "")
if(DEFINED picojson_FIND_DEPENDENCY_NAMES)
  list(APPEND picojson_FIND_DEPENDENCY_NAMES )
  list(REMOVE_DUPLICATES picojson_FIND_DEPENDENCY_NAMES)
else()
  set(picojson_FIND_DEPENDENCY_NAMES )
endif()

########### VARIABLES #######################################################################
#############################################################################################
set(picojson_PACKAGE_FOLDER_RELEASE "/Users/paul/.conan2/p/picojde3f96225d840/p")
set(picojson_BUILD_MODULES_PATHS_RELEASE )


set(picojson_INCLUDE_DIRS_RELEASE "${picojson_PACKAGE_FOLDER_RELEASE}/include")
set(picojson_RES_DIRS_RELEASE )
set(picojson_DEFINITIONS_RELEASE )
set(picojson_SHARED_LINK_FLAGS_RELEASE )
set(picojson_EXE_LINK_FLAGS_RELEASE )
set(picojson_OBJECTS_RELEASE )
set(picojson_COMPILE_DEFINITIONS_RELEASE )
set(picojson_COMPILE_OPTIONS_C_RELEASE )
set(picojson_COMPILE_OPTIONS_CXX_RELEASE )
set(picojson_LIB_DIRS_RELEASE )
set(picojson_BIN_DIRS_RELEASE )
set(picojson_LIBRARY_TYPE_RELEASE UNKNOWN)
set(picojson_IS_HOST_WINDOWS_RELEASE 0)
set(picojson_LIBS_RELEASE )
set(picojson_SYSTEM_LIBS_RELEASE )
set(picojson_FRAMEWORK_DIRS_RELEASE )
set(picojson_FRAMEWORKS_RELEASE )
set(picojson_BUILD_DIRS_RELEASE )
set(picojson_NO_SONAME_MODE_RELEASE FALSE)


# COMPOUND VARIABLES
set(picojson_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${picojson_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${picojson_COMPILE_OPTIONS_C_RELEASE}>")
set(picojson_LINKER_FLAGS_RELEASE
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${picojson_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${picojson_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${picojson_EXE_LINK_FLAGS_RELEASE}>")


set(picojson_COMPONENTS_RELEASE )