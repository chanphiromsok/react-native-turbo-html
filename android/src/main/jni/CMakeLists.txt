# Built into the app's `appmodules` via autolinking (react-native.config.js → cmakeListsPath).
# Compiles the codegen Props/EventEmitters plus our hand-written measuring ShadowNode.
cmake_minimum_required(VERSION 3.13)
set(CMAKE_VERBOSE_MAKEFILE ON)

set(LIB_LITERAL TurboHtmlViewSpec)
set(LIB_TARGET_NAME react_codegen_${LIB_LITERAL})

set(LIB_ANDROID_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../..)
set(LIB_COMMON_DIR ${LIB_ANDROID_DIR}/../cpp)
set(LIB_COMMON_COMPONENTS_DIR ${LIB_COMMON_DIR}/react/renderer/components/${LIB_LITERAL})
set(LIB_ANDROID_GENERATED_JNI_DIR ${LIB_ANDROID_DIR}/build/generated/source/codegen/jni)
set(LIB_ANDROID_GENERATED_COMPONENTS_DIR ${LIB_ANDROID_GENERATED_JNI_DIR}/react/renderer/components/${LIB_LITERAL})

file(GLOB LIB_CUSTOM_SRCS CONFIGURE_DEPENDS *.cpp ${LIB_COMMON_COMPONENTS_DIR}/*.cpp)
file(GLOB LIB_CODEGEN_SRCS CONFIGURE_DEPENDS ${LIB_ANDROID_GENERATED_COMPONENTS_DIR}/*.cpp)

add_library(${LIB_TARGET_NAME} SHARED ${LIB_CUSTOM_SRCS} ${LIB_CODEGEN_SRCS})

# `.` first so our TurboHtmlViewSpec.h wins over the codegen one.
target_include_directories(
  ${LIB_TARGET_NAME}
  PUBLIC
  .
  ${LIB_COMMON_DIR}
  ${LIB_ANDROID_GENERATED_JNI_DIR}
  ${LIB_ANDROID_GENERATED_COMPONENTS_DIR}
)

target_link_libraries(
  ${LIB_TARGET_NAME}
  ReactAndroid::reactnative
  ReactAndroid::jsi
  fbjni::fbjni
)

target_compile_reactnative_options(${LIB_TARGET_NAME} PRIVATE)

target_include_directories(${CMAKE_PROJECT_NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
