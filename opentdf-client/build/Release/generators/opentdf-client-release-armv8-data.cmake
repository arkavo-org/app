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
set(opentdf-client_PACKAGE_FOLDER_RELEASE "/Users/paul/.conan2/p/b/opentb229b9fc6e01d/p")
set(opentdf-client_BUILD_MODULES_PATHS_RELEASE )


set(opentdf-client_INCLUDE_DIRS_RELEASE "${opentdf-client_PACKAGE_FOLDER_RELEASE}/include")
set(opentdf-client_RES_DIRS_RELEASE )
set(opentdf-client_DEFINITIONS_RELEASE )
set(opentdf-client_SHARED_LINK_FLAGS_RELEASE )
set(opentdf-client_EXE_LINK_FLAGS_RELEASE )
set(opentdf-client_OBJECTS_RELEASE )
set(opentdf-client_COMPILE_DEFINITIONS_RELEASE )
set(opentdf-client_COMPILE_OPTIONS_C_RELEASE )
set(opentdf-client_COMPILE_OPTIONS_CXX_RELEASE )
set(opentdf-client_LIB_DIRS_RELEASE "${opentdf-client_PACKAGE_FOLDER_RELEASE}/lib")
set(opentdf-client_BIN_DIRS_RELEASE )
set(opentdf-client_LIBRARY_TYPE_RELEASE STATIC)
set(opentdf-client_IS_HOST_WINDOWS_RELEASE 0)
set(opentdf-client_LIBS_RELEASE opentdf_static)
set(opentdf-client_SYSTEM_LIBS_RELEASE )
set(opentdf-client_FRAMEWORK_DIRS_RELEASE )
set(opentdf-client_FRAMEWORKS_RELEASE )
set(opentdf-client_BUILD_DIRS_RELEASE )
set(opentdf-client_NO_SONAME_MODE_RELEASE FALSE)


# COMPOUND VARIABLES
set(opentdf-client_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${opentdf-client_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${opentdf-client_COMPILE_OPTIONS_C_RELEASE}>")
set(opentdf-client_LINKER_FLAGS_RELEASE
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${opentdf-client_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${opentdf-client_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${opentdf-client_EXE_LINK_FLAGS_RELEASE}>")


set(opentdf-client_COMPONENTS_RELEASE copentdf-client::opentdf-client)
########### COMPONENT copentdf-client::opentdf-client VARIABLES ############################################

set(opentdf-client_copentdf-client_opentdf-client_INCLUDE_DIRS_RELEASE "${opentdf-client_PACKAGE_FOLDER_RELEASE}/include")
set(opentdf-client_copentdf-client_opentdf-client_LIB_DIRS_RELEASE "${opentdf-client_PACKAGE_FOLDER_RELEASE}/lib")
set(opentdf-client_copentdf-client_opentdf-client_BIN_DIRS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_LIBRARY_TYPE_RELEASE STATIC)
set(opentdf-client_copentdf-client_opentdf-client_IS_HOST_WINDOWS_RELEASE 0)
set(opentdf-client_copentdf-client_opentdf-client_RES_DIRS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_DEFINITIONS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_OBJECTS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_COMPILE_DEFINITIONS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_C_RELEASE "")
set(opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_CXX_RELEASE "")
set(opentdf-client_copentdf-client_opentdf-client_LIBS_RELEASE opentdf_static)
set(opentdf-client_copentdf-client_opentdf-client_SYSTEM_LIBS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_FRAMEWORK_DIRS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_DEPENDENCIES_RELEASE openssl::openssl boost::boost LibXml2::LibXml2 jwt-cpp::jwt-cpp ZLIB::ZLIB)
set(opentdf-client_copentdf-client_opentdf-client_SHARED_LINK_FLAGS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_EXE_LINK_FLAGS_RELEASE )
set(opentdf-client_copentdf-client_opentdf-client_NO_SONAME_MODE_RELEASE FALSE)

# COMPOUND VARIABLES
set(opentdf-client_copentdf-client_opentdf-client_LINKER_FLAGS_RELEASE
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${opentdf-client_copentdf-client_opentdf-client_SHARED_LINK_FLAGS_RELEASE}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${opentdf-client_copentdf-client_opentdf-client_SHARED_LINK_FLAGS_RELEASE}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${opentdf-client_copentdf-client_opentdf-client_EXE_LINK_FLAGS_RELEASE}>
)
set(opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_C_RELEASE}>")