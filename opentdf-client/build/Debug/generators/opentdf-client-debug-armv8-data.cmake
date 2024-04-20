########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

list(APPEND opentdf-client_COMPONENT_NAMES copentdf-client::opentdf-client)
list(REMOVE_DUPLICATES opentdf-client_COMPONENT_NAMES)
if(DEFINED opentdf-client_FIND_DEPENDENCY_NAMES)
  list(APPEND opentdf-client_FIND_DEPENDENCY_NAMES jwt-cpp OpenSSL Boost libxml2 ZLIB)
  list(REMOVE_DUPLICATES opentdf-client_FIND_DEPENDENCY_NAMES)
else()
  set(opentdf-client_FIND_DEPENDENCY_NAMES jwt-cpp OpenSSL Boost libxml2 ZLIB)
endif()
set(jwt-cpp_FIND_MODE "NO_MODULE")
set(OpenSSL_FIND_MODE "NO_MODULE")
set(Boost_FIND_MODE "NO_MODULE")
set(libxml2_FIND_MODE "NO_MODULE")
set(ZLIB_FIND_MODE "NO_MODULE")

########### VARIABLES #######################################################################
#############################################################################################
set(opentdf-client_PACKAGE_FOLDER_DEBUG "/Users/paul/.conan2/p/b/opentab3bfc240f245/p")
set(opentdf-client_BUILD_MODULES_PATHS_DEBUG )


set(opentdf-client_INCLUDE_DIRS_DEBUG "${opentdf-client_PACKAGE_FOLDER_DEBUG}/include")
set(opentdf-client_RES_DIRS_DEBUG )
set(opentdf-client_DEFINITIONS_DEBUG )
set(opentdf-client_SHARED_LINK_FLAGS_DEBUG )
set(opentdf-client_EXE_LINK_FLAGS_DEBUG )
set(opentdf-client_OBJECTS_DEBUG )
set(opentdf-client_COMPILE_DEFINITIONS_DEBUG )
set(opentdf-client_COMPILE_OPTIONS_C_DEBUG )
set(opentdf-client_COMPILE_OPTIONS_CXX_DEBUG )
set(opentdf-client_LIB_DIRS_DEBUG "${opentdf-client_PACKAGE_FOLDER_DEBUG}/lib")
set(opentdf-client_BIN_DIRS_DEBUG )
set(opentdf-client_LIBRARY_TYPE_DEBUG STATIC)
set(opentdf-client_IS_HOST_WINDOWS_DEBUG 0)
set(opentdf-client_LIBS_DEBUG opentdf_static)
set(opentdf-client_SYSTEM_LIBS_DEBUG )
set(opentdf-client_FRAMEWORK_DIRS_DEBUG )
set(opentdf-client_FRAMEWORKS_DEBUG )
set(opentdf-client_BUILD_DIRS_DEBUG )
set(opentdf-client_NO_SONAME_MODE_DEBUG FALSE)


# COMPOUND VARIABLES
set(opentdf-client_COMPILE_OPTIONS_DEBUG
    "$<$<COMPILE_LANGUAGE:CXX>:${opentdf-client_COMPILE_OPTIONS_CXX_DEBUG}>"
    "$<$<COMPILE_LANGUAGE:C>:${opentdf-client_COMPILE_OPTIONS_C_DEBUG}>")
set(opentdf-client_LINKER_FLAGS_DEBUG
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${opentdf-client_SHARED_LINK_FLAGS_DEBUG}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${opentdf-client_SHARED_LINK_FLAGS_DEBUG}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${opentdf-client_EXE_LINK_FLAGS_DEBUG}>")


set(opentdf-client_COMPONENTS_DEBUG copentdf-client::opentdf-client)
########### COMPONENT copentdf-client::opentdf-client VARIABLES ############################################

set(opentdf-client_copentdf-client_opentdf-client_INCLUDE_DIRS_DEBUG "${opentdf-client_PACKAGE_FOLDER_DEBUG}/include")
set(opentdf-client_copentdf-client_opentdf-client_LIB_DIRS_DEBUG "${opentdf-client_PACKAGE_FOLDER_DEBUG}/lib")
set(opentdf-client_copentdf-client_opentdf-client_BIN_DIRS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_LIBRARY_TYPE_DEBUG STATIC)
set(opentdf-client_copentdf-client_opentdf-client_IS_HOST_WINDOWS_DEBUG 0)
set(opentdf-client_copentdf-client_opentdf-client_RES_DIRS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_DEFINITIONS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_OBJECTS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_COMPILE_DEFINITIONS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_C_DEBUG "")
set(opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_CXX_DEBUG "")
set(opentdf-client_copentdf-client_opentdf-client_LIBS_DEBUG opentdf_static)
set(opentdf-client_copentdf-client_opentdf-client_SYSTEM_LIBS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_FRAMEWORK_DIRS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_DEPENDENCIES_DEBUG openssl::openssl boost::boost LibXml2::LibXml2 jwt-cpp::jwt-cpp ZLIB::ZLIB)
set(opentdf-client_copentdf-client_opentdf-client_SHARED_LINK_FLAGS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_EXE_LINK_FLAGS_DEBUG )
set(opentdf-client_copentdf-client_opentdf-client_NO_SONAME_MODE_DEBUG FALSE)

# COMPOUND VARIABLES
set(opentdf-client_copentdf-client_opentdf-client_LINKER_FLAGS_DEBUG
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${opentdf-client_copentdf-client_opentdf-client_SHARED_LINK_FLAGS_DEBUG}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${opentdf-client_copentdf-client_opentdf-client_SHARED_LINK_FLAGS_DEBUG}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${opentdf-client_copentdf-client_opentdf-client_EXE_LINK_FLAGS_DEBUG}>
)
set(opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_DEBUG
    "$<$<COMPILE_LANGUAGE:CXX>:${opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_CXX_DEBUG}>"
    "$<$<COMPILE_LANGUAGE:C>:${opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_C_DEBUG}>")