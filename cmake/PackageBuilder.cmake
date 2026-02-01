include_guard(GLOBAL)

include(CMakePackageConfigHelpers)
include(GNUInstallDirs)

function(_package_check_initialized)
    get_property(package_initialized GLOBAL PROPERTY PACKAGE_INITALIZED)
    if(NOT package_initialized)
        message(FATAL_ERROR "package_create() must be called before all other PackageBuilder functions.")
    endif()
endfunction()

function(package_create)

    # If no version is specified, get it from Git
    if(NOT PROJECT_VERSION)
        find_package(Git REQUIRED)

        # Use "git describe" to get version information from Git
        execute_process(
                COMMAND ${GIT_EXECUTABLE} describe --dirty --long --match=v* --tags
                WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
                RESULT_VARIABLE git_result
                OUTPUT_VARIABLE git_output OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_VARIABLE git_error ERROR_STRIP_TRAILING_WHITESPACE)

        # If the result is not "0" an error has occurred
        if(git_result)
            message(FATAL_ERROR "Package version could not be determined: ${git_error}")
        endif()

        # Parse the version string returned by Git
        # Format is "v<MAJOR>.<MINOR>.<PATCH>-<TWEAK>-<GIT_HASH>[-dirty]"
        if(git_output MATCHES "^v([0-9]+)[.]([0-9]+)[.]([0-9]+)-([0-9]+)")
            set(version_major ${CMAKE_MATCH_1})
            set(version_minor ${CMAKE_MATCH_2})
            set(version_patch ${CMAKE_MATCH_3})
            set(version_tweak ${CMAKE_MATCH_4})

            string(APPEND version "${version_major}.${version_minor}.${version_patch}")
        else()
            message(FATAL_ERROR "Git returned an invalid version: ${git_output}")
        endif()

        # The version is considered dirty if there are uncommitted local changes
        if(git_output MATCHES "-dirty$")
            set(version_is_dirty TRUE)
        else()
            set(version_is_dirty FALSE)
        endif()

        # Use "git log" to get the current commit hash from Git
        execute_process(
                COMMAND ${GIT_EXECUTABLE} log -1 --pretty=format:%H
                WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
                RESULT_VARIABLE git_result
                OUTPUT_VARIABLE git_output OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_VARIABLE git_error ERROR_STRIP_TRAILING_WHITESPACE)

        # If the result is not "0" an error has occurred
        if(git_result)
            message(FATAL_ERROR "Package version could not be determined: ${git_error}")
        endif()

        set(version_git_hash ${git_output})

        # Set global CMake variables containing project version information
        set(PROJECT_VERSION ${version} PARENT_SCOPE)
        set(PROJECT_VERSION_MAJOR ${version_major} PARENT_SCOPE)
        set(PROJECT_VERSION_MINOR ${version_minor} PARENT_SCOPE)
        set(PROJECT_VERSION_PATCH ${version_patch} PARENT_SCOPE)
        set(PROJECT_VERSION_TWEAK ${version_tweak} PARENT_SCOPE)
        set(PROJECT_VERSION_IS_DIRTY ${version_is_dirty} PARENT_SCOPE)
        set(PROJECT_VERSION_HASH ${version_git_hash} PARENT_SCOPE)

        set(${PROJECT_NAME}_VERSION ${version} PARENT_SCOPE)
        set(${PROJECT_NAME}_VERSION_MAJOR ${version_major} PARENT_SCOPE)
        set(${PROJECT_NAME}_VERSION_MINOR ${version_minor} PARENT_SCOPE)
        set(${PROJECT_NAME}_VERSION_PATCH ${version_patch} PARENT_SCOPE)
        set(${PROJECT_NAME}_VERSION_TWEAK ${version_tweak} PARENT_SCOPE)
        set(${PROJECT_NAME}_VERSION_IS_DIRTY ${version_is_dirty} PARENT_SCOPE)
        set(${PROJECT_NAME}_VERSION_HASH ${version_git_hash} PARENT_SCOPE)
    endif()

    if(NOT PROJECT_VERSION)
        message(FATAL_ERROR "Package version could not be determined.")
    endif()

    add_custom_target(conan-create
        COMMAND conan create ${PROJECT_SOURCE_DIR}
            --profile=${CMAKE_BINARY_DIR}/conan_host_profile
            -s build_type=${CMAKE_BUILD_TYPE}
            --version=${PROJECT_VERSION}
            --build=missing
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        COMMENT "Creating Conan package host profile"
        VERBATIM
    )

    set_property(GLOBAL PROPERTY PACKAGE_INITALIZED TRUE)
endfunction()

function(package_add_executable target)
    _package_check_initialized()

    add_executable(${target} ${ARGN})

    # Executables don't need to publicly expose headers so all headers are private
    target_include_directories(${target}
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/include
            ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_property(GLOBAL APPEND PROPERTY ${PROJECT_NAME}_TARGETS ${target})
endfunction()

function(package_add_library target)
    _package_check_initialized()

    add_library(${target} ${ARGN})

    target_include_directories(${target}
        PUBLIC
            $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    message("SETTING INCLUDE DIRECTORY: ${CMAKE_CURRENT_SOURCE_DIR}/include")
    message("INSTALL DIR: ${CMAKE_INSTALL_INCLUDEDIR}")

    set_property(GLOBAL APPEND PROPERTY ${PROJECT_NAME}_TARGETS ${target})
    set_property(GLOBAL APPEND PROPERTY ${PROJECT_NAME}_PUBLIC_HEADER_PATHS ${CMAKE_CURRENT_SOURCE_DIR}/include)

    add_library(${PROJECT_NAME}::${target} ALIAS ${target})
endfunction()

function(package_install)
    _package_check_initialized()

    get_property(targets GLOBAL PROPERTY ${PROJECT_NAME}_TARGETS)

    # Set the install destination and namespace
    set(install_destination "${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}")

    if(targets)
        # Create an export package of the targets
        # Use GNUInstallDirs and COMPONENTS
        # See "Deep CMake for Library Authors" https://www.youtube.com/watch?v=m0DwB4OvDXk
        install(
                TARGETS ${targets}
                EXPORT ${PROJECT_NAME}Targets
                ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
                COMPONENT Development
                INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
                COMPONENT Development
                LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
                COMPONENT Runtime
                NAMELINK_COMPONENT Development
                RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
                COMPONENT Runtime)

        # Install the export package
        install(
                EXPORT ${PROJECT_NAME}Targets
                FILE ${PROJECT_NAME}Targets.cmake
                NAMESPACE ${args_NAMESPACE}
                DESTINATION ${install_destination})
    endif()

    # Install public header files for the project
    get_property(public_header_paths GLOBAL PROPERTY ${PROJECT_NAME}_PUBLIC_HEADER_PATHS)
    foreach(public_header_path IN LISTS public_header_paths)
        install(
                DIRECTORY ${public_header_path}/
                DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
                FILES_MATCHING PATTERN "*.h*")
    endforeach()

    # Install public CMake modules for the project
    install(
            DIRECTORY ${PROJECT_SOURCE_DIR}/cmake/
            DESTINATION ${install_destination}
            FILES_MATCHING PATTERN "*.cmake")

    # Generate a package configuration file
    set(config_content "@PACKAGE_INIT@\n")

    string(APPEND config_content "\nlist(APPEND CMAKE_MODULE_PATH \"\${CMAKE_CURRENT_LIST_DIR}\")\n")

    # Include targets file if we have targets installed
    if(targets)
        string(APPEND config_content "\ninclude(\${CMAKE_CURRENT_LIST_DIR}/${PROJECT_NAME}Targets.cmake)")
    endif()

    file(WRITE ${PROJECT_BINARY_DIR}/${PROJECT_NAME}Config.cmake.in "${config_content}")
    configure_package_config_file(
            ${PROJECT_BINARY_DIR}/${PROJECT_NAME}Config.cmake.in
            ${PROJECT_BINARY_DIR}/${PROJECT_NAME}Config.cmake
            INSTALL_DESTINATION ${install_destination})

    # Gather files to be installed
    list(APPEND install_files ${PROJECT_BINARY_DIR}/${PROJECT_NAME}Config.cmake)

    # Generate a package version file
    write_basic_package_version_file(${PROJECT_NAME}ConfigVersion.cmake
            VERSION ${PROJECT_VERSION}
            COMPATIBILITY SameMajorVersion)

    list(APPEND install_files ${PROJECT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake)

    # Install config files for the project
    install(
            FILES ${install_files}
            DESTINATION ${install_destination})

endfunction()
