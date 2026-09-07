#pragma once

#include <string>

namespace duckdb {
namespace ui {

// Inject fork-only UI overlays into HTML shells (theme toggle, path quotes, zh-CN).
// No-op for non-HTML bodies. Idempotent if already injected.
void InjectForkThemeToggle(std::string &html_body);

} // namespace ui
} // namespace duckdb
