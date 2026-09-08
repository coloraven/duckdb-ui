#pragma once

#include "duckdb.hpp"

namespace duckdb {

// Fork extension (distinct from upstream UiExtension / official "ui").
class UiOfflineExtension : public Extension {
public:
#ifdef DUCKDB_CPP_EXTENSION_ENTRY
	void Load(ExtensionLoader &loader) override;
#else
	void Load(DuckDB &db) override;
#endif

	std::string Name() override;
	std::string Version() const override;
};

} // namespace duckdb
