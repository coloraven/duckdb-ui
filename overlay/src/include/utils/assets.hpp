#pragma once

#include <string>

#define CPPHTTPLIB_OPENSSL_SUPPORT
#include "httplib.hpp"

namespace httplib = duckdb_httplib_openssl;

namespace duckdb {
namespace ui {

std::string ExpandHomePath(std::string path);
std::string GuessContentType(const std::string &path);
std::string SanitizeAssetRelativePath(const std::string &request_path);
// Client routes like /notebooks/... should serve index.html (SPA), not be
// cached/served as application/octet-stream files.
bool ShouldSpaFallbackToIndex(const std::string &request_path);
bool ShouldCacheRemoteAsset(const std::string &request_path,
                            const std::string &content_type);
bool TryReadLocalAsset(const std::string &assets_root,
                       const std::string &request_path, std::string &body_out,
                       std::string &content_type_out,
                       std::string &resolved_relpath_out);
bool WriteLocalAsset(const std::string &assets_root,
                     const std::string &request_path, const std::string &body);
bool ServeLocalAsset(const std::string &assets_root,
                     const std::string &request_path, httplib::Response &res);

} // namespace ui
} // namespace duckdb
