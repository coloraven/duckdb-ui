#include "utils/assets.hpp"
#include "utils/theme_inject.hpp"

#include <cerrno>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include <sys/types.h>

#ifdef _WIN32
#include <direct.h>
#endif

namespace duckdb {
namespace ui {

static bool EndsWithIgnoreCase(const std::string &value, const std::string &suffix) {
	if (suffix.size() > value.size()) {
		return false;
	}
	for (size_t i = 0; i < suffix.size(); i++) {
		char a = value[value.size() - suffix.size() + i];
		char b = suffix[i];
		if (a >= 'A' && a <= 'Z') {
			a = static_cast<char>(a - 'A' + 'a');
		}
		if (b >= 'A' && b <= 'Z') {
			b = static_cast<char>(b - 'A' + 'a');
		}
		if (a != b) {
			return false;
		}
	}
	return true;
}

static std::string JoinPath(const std::string &left, const std::string &right) {
	if (left.empty()) {
		return right;
	}
	if (right.empty()) {
		return left;
	}
	const char last = left[left.size() - 1];
	if (last == '/' || last == '\\') {
		return left + right;
	}
	return left + "/" + right;
}

static std::string ParentPath(const std::string &path) {
	const auto pos = path.find_last_of("/\\");
	if (pos == std::string::npos) {
		return std::string();
	}
	if (pos == 0) {
		return "/";
	}
	return path.substr(0, pos);
}

static bool MkdirOne(const std::string &path) {
#ifdef _WIN32
	const int rc = _mkdir(path.c_str());
#else
	const int rc = mkdir(path.c_str(), 0755);
#endif
	return rc == 0 || errno == EEXIST;
}

// C++11-compatible recursive mkdir (DuckDB extension builds use -std=c++11).
static bool CreateDirectories(const std::string &path) {
	if (path.empty()) {
		return false;
	}

	std::string current;
	size_t i = 0;

#ifdef _WIN32
	if (path.size() >= 2 && path[1] == ':') {
		current = path.substr(0, 2);
		i = 2;
		if (i < path.size() && (path[i] == '/' || path[i] == '\\')) {
			current.push_back('\\');
			i++;
		}
	} else if (path[0] == '/' || path[0] == '\\') {
		current = "\\";
		i = 1;
	}
#else
	if (path[0] == '/') {
		current = "/";
		i = 1;
	}
#endif

	while (i < path.size()) {
		while (i < path.size() && (path[i] == '/' || path[i] == '\\')) {
			i++;
		}
		if (i >= path.size()) {
			break;
		}
		size_t j = i;
		while (j < path.size() && path[j] != '/' && path[j] != '\\') {
			j++;
		}
		if (!current.empty() && current[current.size() - 1] != '/' &&
		    current[current.size() - 1] != '\\') {
			current.push_back('/');
		}
		current.append(path, i, j - i);
		if (!MkdirOne(current)) {
			return false;
		}
		i = j;
	}
	return true;
}

static bool IsRegularFile(const std::string &path) {
	struct stat st;
	if (stat(path.c_str(), &st) != 0) {
		return false;
	}
#ifdef _WIN32
	return (st.st_mode & _S_IFREG) != 0;
#else
	return S_ISREG(st.st_mode);
#endif
}

static bool ReadFileBytes(const std::string &file, std::string &body_out) {
	std::ifstream in(file.c_str(), std::ios::binary);
	if (!in) {
		return false;
	}
	std::ostringstream ss;
	ss << in.rdbuf();
	body_out = ss.str();
	return true;
}

std::string ExpandHomePath(std::string path) {
	if (path.empty() || path[0] != '~') {
		return path;
	}
	// On Windows prefer USERPROFILE: Git Bash/MSYS often set HOME to a
	// non-Win32 path like "/c/Users/..." which native DuckDB cannot open.
#ifdef _WIN32
	const char *home = std::getenv("USERPROFILE");
	if (!home) {
		home = std::getenv("HOME");
	}
#else
	const char *home = std::getenv("HOME");
#endif
	if (!home) {
		return path;
	}
	if (path.size() == 1) {
		return std::string(home);
	}
	if (path[1] == '/' || path[1] == '\\') {
		return std::string(home) + path.substr(1);
	}
	return path;
}

std::string GuessContentType(const std::string &path) {
	if (EndsWithIgnoreCase(path, ".html") || EndsWithIgnoreCase(path, ".htm")) {
		return "text/html; charset=utf-8";
	}
	if (EndsWithIgnoreCase(path, ".js") || EndsWithIgnoreCase(path, ".mjs")) {
		return "application/javascript; charset=utf-8";
	}
	if (EndsWithIgnoreCase(path, ".css")) {
		return "text/css; charset=utf-8";
	}
	if (EndsWithIgnoreCase(path, ".json") || path == "config" ||
	    EndsWithIgnoreCase(path, "/config") || path == "version" ||
	    EndsWithIgnoreCase(path, "/version") || path == "manifest" ||
	    EndsWithIgnoreCase(path, "/manifest")) {
		return "application/json; charset=utf-8";
	}
	if (EndsWithIgnoreCase(path, ".svg")) {
		return "image/svg+xml";
	}
	if (EndsWithIgnoreCase(path, ".png")) {
		return "image/png";
	}
	if (EndsWithIgnoreCase(path, ".jpg") || EndsWithIgnoreCase(path, ".jpeg")) {
		return "image/jpeg";
	}
	if (EndsWithIgnoreCase(path, ".webp")) {
		return "image/webp";
	}
	if (EndsWithIgnoreCase(path, ".woff2")) {
		return "font/woff2";
	}
	if (EndsWithIgnoreCase(path, ".woff")) {
		return "font/woff";
	}
	if (EndsWithIgnoreCase(path, ".ttf")) {
		return "font/ttf";
	}
	if (EndsWithIgnoreCase(path, ".wasm")) {
		return "application/wasm";
	}
	if (EndsWithIgnoreCase(path, ".map") || EndsWithIgnoreCase(path, ".txt")) {
		return "text/plain; charset=utf-8";
	}
	return "application/octet-stream";
}

std::string SanitizeAssetRelativePath(const std::string &request_path) {
	std::string path = request_path.empty() ? "/" : request_path;
	auto qpos = path.find('?');
	if (qpos != std::string::npos) {
		path = path.substr(0, qpos);
	}
	auto hpos = path.find('#');
	if (hpos != std::string::npos) {
		path = path.substr(0, hpos);
	}
	if (path.empty() || path == "/") {
		return "index.html";
	}
	if (path[0] == '/') {
		path = path.substr(1);
	}
	if (path.empty() || path.find("..") != std::string::npos) {
		return "";
	}
	return path;
}

static bool HasFileExtension(const std::string &rel_or_path) {
	// Use the last path segment only (notebooks/foo.bar is a file; notebooks/foo is not).
	std::string name = rel_or_path;
	auto slash = name.find_last_of("/\\");
	if (slash != std::string::npos) {
		name = name.substr(slash + 1);
	}
	auto dot = name.find_last_of('.');
	return dot != std::string::npos && dot > 0 && dot + 1 < name.size();
}

static bool IsExactShellApiPath(const std::string &request_path) {
	std::string path = request_path.empty() ? "/" : request_path;
	auto qpos = path.find('?');
	if (qpos != std::string::npos) {
		path = path.substr(0, qpos);
	}
	auto hpos = path.find('#');
	if (hpos != std::string::npos) {
		path = path.substr(0, hpos);
	}
	while (path.size() > 1 && path.back() == '/') {
		path.pop_back();
	}
	return path == "/version" || path == "/config" || path == "/manifest" ||
	       path == "version" || path == "config" || path == "manifest";
}

bool ShouldSpaFallbackToIndex(const std::string &request_path) {
	if (IsExactShellApiPath(request_path)) {
		return false;
	}
	auto rel = SanitizeAssetRelativePath(request_path);
	if (rel.empty() || rel == "index.html") {
		return false;
	}
	// Real static files keep their path; client routes have no extension.
	return !HasFileExtension(rel);
}

bool ShouldCacheRemoteAsset(const std::string &request_path,
                            const std::string &content_type) {
	if (ShouldSpaFallbackToIndex(request_path)) {
		// Never cache SPA HTML under /notebooks/... etc. — next local serve
		// would guess application/octet-stream and browsers offer "Save as".
		return false;
	}
	if (content_type.find("text/html") != std::string::npos) {
		auto rel = SanitizeAssetRelativePath(request_path);
		if (!rel.empty() && !HasFileExtension(rel) && rel != "index.html") {
			return false;
		}
	}
	return true;
}

bool TryReadLocalAsset(const std::string &assets_root, const std::string &request_path,
                       std::string &body_out, std::string &content_type_out,
                       std::string &resolved_relpath_out) {
	if (assets_root.empty()) {
		return false;
	}
	auto rel = SanitizeAssetRelativePath(request_path);
	if (rel.empty()) {
		return false;
	}

	// Client routes (/notebooks/..., etc.): always serve the SPA shell.
	// Ignore any previously cached extensionless blob at that path.
	if (ShouldSpaFallbackToIndex(request_path)) {
		rel = "index.html";
	}

	std::string candidate = JoinPath(assets_root, rel);
	if (!IsRegularFile(candidate)) {
		return false;
	}

	if (!ReadFileBytes(candidate, body_out)) {
		return false;
	}
	content_type_out = GuessContentType(rel);
	resolved_relpath_out = rel;
	return true;
}

bool WriteLocalAsset(const std::string &assets_root, const std::string &request_path,
                     const std::string &body) {
	if (assets_root.empty()) {
		return false;
	}
	auto rel = SanitizeAssetRelativePath(request_path);
	if (rel.empty()) {
		return false;
	}
	const std::string dest = JoinPath(assets_root, rel);
	const std::string parent = ParentPath(dest);
	if (!parent.empty() && !CreateDirectories(parent)) {
		return false;
	}
	std::ofstream out(dest.c_str(), std::ios::binary | std::ios::trunc);
	if (!out) {
		return false;
	}
	out.write(body.data(), static_cast<std::streamsize>(body.size()));
	return static_cast<bool>(out);
}

bool ServeLocalAsset(const std::string &assets_root, const std::string &request_path,
                     httplib::Response &res) {
	std::string body;
	std::string content_type;
	std::string resolved;
	if (!TryReadLocalAsset(assets_root, request_path, body, content_type, resolved)) {
		return false;
	}
	if (content_type.find("text/html") != std::string::npos) {
		InjectForkThemeToggle(body);
	}
	res.status = 200;
	res.set_content(body, content_type);
	res.set_header("X-DuckDB-UI-Asset-Source", "local");
	res.set_header("X-DuckDB-UI-Asset-Path", resolved);
	return true;
}

} // namespace ui
} // namespace duckdb
