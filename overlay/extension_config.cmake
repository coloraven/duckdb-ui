# This file is included by DuckDB's build system. It specifies which extension to load.
# Fork: load as ui_offline so the artifact never collides with official ui.duckdb_extension.

duckdb_extension_load(ui_offline
    SOURCE_DIR ${CMAKE_CURRENT_LIST_DIR}
    LOAD_TESTS
)
