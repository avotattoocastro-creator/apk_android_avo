# Android NDK build of the engine + JNI bridge (arm64-v8a, armeabi-v7a, x86_64).
cmake_minimum_required(VERSION 3.18)
project(avo_equine_android CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../.. avo_eq_build)
add_library(avo_equine_jni SHARED jni/avo_eq_jni.cpp)
target_link_libraries(avo_equine_jni avo_eq)
