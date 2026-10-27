cmake_minimum_required(VERSION 3.12)
project(read_table)
option(PRINT_DATA "Print out the table data. Requires arrow-glib" ON)
option(VERBOSE "Enable for more diagnostics messages." OFF)
option(UDT_IN_DEV "Test UDT schema round trips. Requires delta_kernel_ffi with udt-in-dev." OFF)
option(
  GEO_TYPE_IN_DEV
  "Register the geometry/geography schema test. Requires delta_kernel_ffi built with --features geo-type-in-dev."
  OFF)
add_executable(read_table read_table.c arrow.c ../common/kernel_utils.c)
target_compile_definitions(read_table PUBLIC DEFINE_DEFAULT_ENGINE_BASE)
target_include_directories(read_table PUBLIC 
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/ffi-headers"
    "${CMAKE_CURRENT_SOURCE_DIR}/../common")
target_link_directories(read_table PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/debug")
target_link_libraries(read_table PUBLIC delta_kernel_ffi)
target_compile_options(read_table PUBLIC)

# The C string model rejects embedded NULs. UDT_IN_DEV enables the engine-backed annotation
# round trip against the schema-only Delta fixture.
include(CTest)
add_executable(udt_annotation_test udt_annotation_test.c ../common/kernel_utils.c)
target_compile_definitions(udt_annotation_test PUBLIC DEFINE_DEFAULT_ENGINE_BASE)
target_include_directories(udt_annotation_test PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/ffi-headers"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common")
target_link_directories(udt_annotation_test PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/debug")
target_link_libraries(udt_annotation_test PUBLIC delta_kernel_ffi)
add_test(NAME udt_annotation_rejects_embedded_nul COMMAND udt_annotation_test --embedded-nul)
set_tests_properties(udt_annotation_rejects_embedded_nul PROPERTIES WILL_FAIL TRUE)
if(UDT_IN_DEV)
  add_test(NAME udt_annotation_round_trip COMMAND udt_annotation_test
    "${CMAKE_CURRENT_SOURCE_DIR}/../../tests/read-table-testing/udt-annotations/")
endif()
add_executable(commit_range_commit_files commit_range_commit_files.c ../common/kernel_utils.c)
target_compile_definitions(commit_range_commit_files PUBLIC DEFINE_DEFAULT_ENGINE_BASE)
target_include_directories(commit_range_commit_files PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/ffi-headers"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common")
target_link_directories(commit_range_commit_files PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/debug")
target_link_libraries(commit_range_commit_files PUBLIC delta_kernel_ffi)
set(TestRunner "../../../tests/run_and_diff.sh")
set(DatPath "../../../../acceptance/tests/dat/out/reader_tests/generated")
set(ExpectedPath "../../../tests/read-table-testing/expected-data")
set(KernelTestPath "../../../../kernel/tests/data")
add_test(NAME read_and_print_all_prim COMMAND ${TestRunner} ${ExpectedPath}/all-prim-types.expected ./read_table ${DatPath}/all_primitive_types/delta/)
add_test(NAME read_and_print_all_prim_cols COMMAND ${TestRunner} ${ExpectedPath}/all-prim-types-cols.expected ./read_table -cdecimal,float64 ${DatPath}/all_primitive_types/delta/)
add_test(NAME read_and_print_nested COMMAND ${TestRunner} ${ExpectedPath}/nested-types.expected ./read_table ${DatPath}/nested_types/delta/)
add_test(NAME read_and_print_nested_cols COMMAND ${TestRunner} ${ExpectedPath}/nested-types-cols.expected ./read_table -cmap,struct,array ${DatPath}/nested_types/delta/)
add_test(NAME read_and_print_basic_partitioned COMMAND ${TestRunner} ${ExpectedPath}/basic-partitioned.expected ./read_table ${DatPath}/basic_partitioned/delta/)
add_test(NAME read_and_print_with_dv_small COMMAND ${TestRunner} ${ExpectedPath}/table-with-dv-small.expected ./read_table ${KernelTestPath}/table-with-dv-small/)
add_test(NAME read_and_print_void_col COMMAND ${TestRunner} ${ExpectedPath}/void-column.expected ./read_table -cid,void_col ${KernelTestPath}/void-column/)
add_test(NAME read_and_print_with_short_dv COMMAND ${TestRunner} ${ExpectedPath}/with-short-dv.expected ./read_table ${KernelTestPath}/with-short-dv/)
# Exercises the Arrow batch-mode scan metadata path (scan_metadata_next_arrow). The arrow path
# does not call read_parquet_file, so the data section is "[No data]"; this test still
# requires PRINT_DATA=ON because iterate_scan_metadata_arrow is gated behind it.
add_test(NAME read_arrow_metadata_basic COMMAND ${TestRunner} ${ExpectedPath}/basic-partitioned-arrow-metadata.expected ./read_table -a ${DatPath}/basic_partitioned/delta/)
# Exercises typed field metadata across the FFI: the column_mapping table's fields carry
# `delta.columnMapping.id`, which the schema visitor reads back via get_from_metadata_map and
# prints per field.
add_test(NAME read_column_mapping_metadata COMMAND ${TestRunner} ${ExpectedPath}/column-mapping-arrow-metadata.expected ./read_table -a ${DatPath}/column_mapping/delta/)
add_test(NAME read_projected_column_mapping COMMAND ${TestRunner} ${ExpectedPath}/column-mapping-projected.expected ./read_table -cletter,new_int ${DatPath}/column_mapping/delta/)
add_test(NAME commit_range_commit_files_basic_partitioned
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/../../tests/read-table-testing/run_commit_range_commit_files_test.sh"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../acceptance/tests/dat/out/reader_tests/generated/basic_partitioned/delta/"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../tests/read-table-testing/expected-data/commit-range-commit-files-basic-partitioned.expected")
if(GEO_TYPE_IN_DEV)
  target_compile_definitions(read_table PUBLIC DEFINE_GEO_TYPE_IN_DEV)
  add_test(NAME read_and_print_geo COMMAND ${TestRunner} ${ExpectedPath}/table-with-geo.expected ./read_table ${KernelTestPath}/table-with-geo/)
  add_test(NAME read_and_print_projected_geo COMMAND ${TestRunner} ${ExpectedPath}/table-with-geo-cols.expected ./read_table -cgeom,geog -s ${KernelTestPath}/table-with-geo/)
endif()

if(WIN32)
  set(CMAKE_C_FLAGS_DEBUG "/MT")
  target_link_libraries(read_table PUBLIC ws2_32 userenv bcrypt ncrypt crypt32 secur32 ntdll RuntimeObject)
endif(WIN32)

if(MSVC)
  target_compile_options(read_table PRIVATE /W3 /WX)
  target_compile_options(udt_annotation_test PRIVATE /W3 /WX)
  target_compile_options(commit_range_commit_files PRIVATE /W3 /WX)
else()
  # no-strict-prototypes because arrow headers have fn defs without prototypes
  target_compile_options(read_table PRIVATE -Wall -Wextra -Wpedantic -Werror -Wno-strict-prototypes -g -fsanitize=address)
  target_link_options(read_table PRIVATE -g -fsanitize=address)
  target_compile_options(udt_annotation_test PRIVATE -Wall -Wextra -Wpedantic -Werror -Wno-strict-prototypes -g -fsanitize=address)
  target_link_options(udt_annotation_test PRIVATE -g -fsanitize=address)
  target_compile_options(commit_range_commit_files PRIVATE -Wall -Wextra -Wpedantic -Werror -Wno-strict-prototypes -g -fsanitize=address)
  target_link_options(commit_range_commit_files PRIVATE -g -fsanitize=address)
endif()

if(VERBOSE)
  target_compile_definitions(read_table PUBLIC VERBOSE)
endif(VERBOSE)

if(PRINT_DATA)
  include(FindPkgConfig)
  pkg_check_modules(GLIB REQUIRED glib-2.0)
  pkg_check_modules(ARROW_GLIB REQUIRED arrow-glib)
  target_include_directories(read_table PUBLIC ${ARROW_GLIB_INCLUDE_DIRS})
  target_link_directories(read_table PUBLIC ${ARROW_GLIB_LIBRARY_DIRS})
  target_link_libraries(read_table PUBLIC ${ARROW_GLIB_LIBRARIES})
  # arrow-glib's .pc file (as of v19) leaks `-std=c++11` into CFLAGS; that's a C++ flag
  # which the C compiler rejects under -Werror. Drop any -std= flags before forwarding.
  set(ARROW_GLIB_CFLAGS_FILTERED "")
  foreach(flag ${ARROW_GLIB_CFLAGS_OTHER})
    if(NOT flag MATCHES "^-std=")
      list(APPEND ARROW_GLIB_CFLAGS_FILTERED ${flag})
    endif()
  endforeach()
  target_compile_options(read_table PUBLIC ${ARROW_GLIB_CFLAGS_FILTERED})
  target_compile_definitions(read_table PUBLIC PRINT_ARROW_DATA)
endif(PRINT_DATA)
