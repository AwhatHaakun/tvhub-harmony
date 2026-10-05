# CMakeLists.txt —— QuickJS 鸿蒙 NAPI 模块编译配置
# 前提：把 QuickJS 源码放入本目录下的 quickjs/（见 README 第 6 节）
cmake_minimum_required(VERSION 3.5.0)
project(quickjs)

set(QUICKJS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/quickjs)

# NAPI 封装 + QuickJS 核心源文件（新版 QuickJS 已移除 libbf，新增 dtoa）
add_library(quickjs SHARED
    quickjs_napi.cpp
    ${QUICKJS_DIR}/quickjs.c
    ${QUICKJS_DIR}/dtoa.c
    ${QUICKJS_DIR}/libregexp.c
    ${QUICKJS_DIR}/libunicode.c
    ${QUICKJS_DIR}/cutils.c
    ${QUICKJS_DIR}/quickjs-libc.c
)

target_include_directories(quickjs PUBLIC ${QUICKJS_DIR})

# QuickJS 官方 Makefile 使用的宏（版本号取自 cpp/quickjs/VERSION）
target_compile_definitions(quickjs PRIVATE
    CONFIG_VERSION=\"2026-06-04\"
    _GNU_SOURCE
)

# quickjs-libc.c 需要 POSIX 扩展（select/poll 等），用 gnu 标准
set_target_properties(quickjs PROPERTIES
    C_STANDARD 11
    CXX_STANDARD 17
)

# libace_napi.z.so 为鸿蒙 NAPI 运行库；m 为数学库，pthread 为 QuickJS 线程支持
target_link_libraries(quickjs PUBLIC libace_napi.z.so m pthread)
