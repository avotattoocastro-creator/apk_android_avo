cmake_minimum_required(VERSION 3.16)
project(avo_equine_intelligence VERSION 1.0.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(AVO_EQ_SANITIZE "Build with AddressSanitizer + UndefinedBehaviorSanitizer" OFF)
if(AVO_EQ_SANITIZE AND NOT MSVC)
  add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()
if(NOT MSVC)
  add_compile_options(-Wall -Wextra -Wno-unused-parameter)
endif()

# The RAW session format is read with the same avo_core code that the chest uses to write it.
set(AVO_CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../firmware/back/V3_8_0/lib/avo_core/src CACHE PATH "avo_core sources")
file(GLOB AVO_CORE_SRC ${AVO_CORE_DIR}/*.cpp)

file(GLOB_RECURSE EQ_SRC ${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp)
add_library(avo_eq STATIC ${EQ_SRC} ${AVO_CORE_SRC})
target_compile_definitions(avo_eq PUBLIC AVO_EQ_STATIC)
target_include_directories(avo_eq PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include PRIVATE ${AVO_CORE_DIR})

# Shared library with the C API (Android JNI, Windows P/Invoke, Python ctypes)
add_library(avo_eq_shared SHARED ${EQ_SRC} ${AVO_CORE_SRC})
target_include_directories(avo_eq_shared PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include PRIVATE ${AVO_CORE_DIR})
target_compile_definitions(avo_eq_shared PRIVATE AVO_EQ_BUILD_DLL)
set_target_properties(avo_eq_shared PROPERTIES OUTPUT_NAME avo_equine)

add_executable(avo_eq_cli tools/session-inspector/avo_eq_cli.cpp)
target_link_libraries(avo_eq_cli avo_eq)

enable_testing()
add_executable(avo_eq_tests tests/test_main.cpp tests/test_dsp.cpp tests/test_gnss.cpp tests/test_sync.cpp tests/test_motion.cpp tests/test_ingestion.cpp)
target_include_directories(avo_eq_tests PRIVATE ${AVO_CORE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/tests)
target_link_libraries(avo_eq_tests avo_eq)
add_test(NAME avo_eq_tests COMMAND avo_eq_tests)
