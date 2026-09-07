#pragma once

#include <duckdb/common/exception.hpp>
#include <duckdb/main/client_context.hpp>

#define UI_LOCAL_PORT_SETTING_NAME "ui_local_port"
#define UI_LOCAL_PORT_SETTING_DEFAULT 4213
#define UI_LOCAL_HOST_SETTING_NAME "ui_local_host"
// Windows getaddrinfo("localhost") prefers ::1; default to IPv4 loopback so
// http://127.0.0.1:port works. Override with SET ui_local_host='...' if needed.
#ifdef _WIN32
#define UI_LOCAL_HOST_SETTING_DEFAULT "127.0.0.1"
#else
#define UI_LOCAL_HOST_SETTING_DEFAULT "localhost"
#endif
#define UI_REMOTE_URL_SETTING_NAME "ui_remote_url"
#define UI_REMOTE_URL_SETTING_DEFAULT "https://ui.duckdb.org"
#define UI_POLLING_INTERVAL_SETTING_NAME "ui_polling_interval"
#define UI_POLLING_INTERVAL_SETTING_DEFAULT 284
#define UI_ASSETS_PATH_SETTING_NAME "ui_assets_path"
#define UI_ASSETS_PATH_SETTING_DEFAULT "~/.duckdb/extension_data/ui/assets"
#define UI_OFFLINE_SETTING_NAME "ui_offline"
#define UI_OFFLINE_SETTING_DEFAULT false

namespace duckdb {

namespace internal {

template <typename T>
T GetSetting(const ClientContext &context, const char *setting_name) {
  Value value;
  if (!context.TryGetCurrentSetting(setting_name, value)) {
    throw Exception(ExceptionType::SETTINGS,
                    "Setting \"" + std::string(setting_name) + "\" not found");
  }
  return value.GetValue<T>();
}
} // namespace internal

std::string GetRemoteUrl(const ClientContext &);
uint16_t GetLocalPort(const ClientContext &);
std::string GetLocalHost(const ClientContext &);
uint32_t GetPollingInterval(const ClientContext &);
std::string GetAssetsPath(const ClientContext &);
bool GetOfflineMode(const ClientContext &);

} // namespace duckdb
