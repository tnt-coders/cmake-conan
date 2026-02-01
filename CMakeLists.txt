cmake_minimum_required(VERSION 3.24)

project(CMakeConan VERSION 1.0.0 LANGUAGES CXX)

# Add cmake packages to the module path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} PARENT_SCOPE)
