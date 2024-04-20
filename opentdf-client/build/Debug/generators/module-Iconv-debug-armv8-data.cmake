########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

set(libiconv_COMPONENT_NAMES "")
if(DEFINED libiconv_FIND_DEPENDENCY_NAMES)
  list(APPEND libiconv_FIND_DEPENDENCY_NAMES )
  list(REMOVE_DUPLICATES libiconv_FIND_DEPENDENCY_NAMES)
else()
  set(libiconv_FIND_DEPENDENCY_NAMES )
endif()

########### VARIABLES #######################################################################
#############################################################################################
set(libiconv_PACKAGE_FOLDER_DEBUG "/Users/paul/.conan2/p/b/libic9358fd979acfc/p")
set(libiconv_BUILD_MODULES_PATHS_DEBUG )


set(libiconv_INCLUDE_DIRS_DEBUG )
set(libiconv_RES_DIRS_DEBUG )
set(libiconv_DEFINITIONS_DEBUG )
set(libiconv_SHARED_LINK_FLAGS_DEBUG )
set(libiconv_EXE_LINK_FLAGS_DEBUG )
set(libiconv_OBJECTS_DEBUG )
set(libiconv_COMPILE_DEFINITIONS_DEBUG )
set(libiconv_COMPILE_OPTIONS_C_DEBUG )
set(libiconv_COMPILE_OPTIONS_CXX_DEBUG )
set(libiconv_LIB_DIRS_DEBUG "${libiconv_PACKAGE_FOLDER_DEBUG}/lib")
set(libiconv_BIN_DIRS_DEBUG )
set(libiconv_LIBRARY_TYPE_DEBUG STATIC)
set(libiconv_IS_HOST_WINDOWS_DEBUG 0)
set(libiconv_LIBS_DEBUG iconv charset)
set(libiconv_SYSTEM_LIBS_DEBUG )
set(libiconv_FRAMEWORK_DIRS_DEBUG )
set(libiconv_FRAMEWORKS_DEBUG )
set(libiconv_BUILD_DIRS_DEBUG )
set(libiconv_NO_SONAME_MODE_DEBUG FALSE)


# COMPOUND VARIABLES
set(libiconv_COMPILE_OPTIONS_DEBUG
    "$<$<COMPILE_LANGUAGE:CXX>:${libiconv_COMPILE_OPTIONS_CXX_DEBUG}>"
    "$<$<COMPILE_LANGUAGE:C>:${libiconv_COMPILE_OPTIONS_C_DEBUG}>")
set(libiconv_LINKER_FLAGS_DEBUG
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${libiconv_SHARED_LINK_FLAGS_DEBUG}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${libiconv_SHARED_LINK_FLAGS_DEBUG}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${libiconv_EXE_LINK_FLAGS_DEBUG}>")


set(libiconv_COMPONENTS_DEBUG )