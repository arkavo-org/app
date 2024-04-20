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
set(picojson_PACKAGE_FOLDER_DEBUG "/Users/paul/.conan2/p/picojde3f96225d840/p")
set(picojson_BUILD_MODULES_PATHS_DEBUG )


set(picojson_INCLUDE_DIRS_DEBUG "${picojson_PACKAGE_FOLDER_DEBUG}/include")
set(picojson_RES_DIRS_DEBUG )
set(picojson_DEFINITIONS_DEBUG )
set(picojson_SHARED_LINK_FLAGS_DEBUG )
set(picojson_EXE_LINK_FLAGS_DEBUG )
set(picojson_OBJECTS_DEBUG )
set(picojson_COMPILE_DEFINITIONS_DEBUG )
set(picojson_COMPILE_OPTIONS_C_DEBUG )
set(picojson_COMPILE_OPTIONS_CXX_DEBUG )
set(picojson_LIB_DIRS_DEBUG )
set(picojson_BIN_DIRS_DEBUG )
set(picojson_LIBRARY_TYPE_DEBUG UNKNOWN)
set(picojson_IS_HOST_WINDOWS_DEBUG 0)
set(picojson_LIBS_DEBUG )
set(picojson_SYSTEM_LIBS_DEBUG )
set(picojson_FRAMEWORK_DIRS_DEBUG )
set(picojson_FRAMEWORKS_DEBUG )
set(picojson_BUILD_DIRS_DEBUG )
set(picojson_NO_SONAME_MODE_DEBUG FALSE)


# COMPOUND VARIABLES
set(picojson_COMPILE_OPTIONS_DEBUG
    "$<$<COMPILE_LANGUAGE:CXX>:${picojson_COMPILE_OPTIONS_CXX_DEBUG}>"
    "$<$<COMPILE_LANGUAGE:C>:${picojson_COMPILE_OPTIONS_C_DEBUG}>")
set(picojson_LINKER_FLAGS_DEBUG
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${picojson_SHARED_LINK_FLAGS_DEBUG}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${picojson_SHARED_LINK_FLAGS_DEBUG}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${picojson_EXE_LINK_FLAGS_DEBUG}>")


set(picojson_COMPONENTS_DEBUG )