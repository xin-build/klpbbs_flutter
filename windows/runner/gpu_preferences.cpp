#include "gpu_preferences.h"
#include "gpu_adapter_identity.h"

#include <windows.h>
#include <dxgi1_2.h>
#include <d3dkmthk.h>
#include <shlobj.h>
#include <shellapi.h>
#include <wrl/client.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <algorithm>
#include <cwctype>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <map>
#include <vector>
#include <system_error>
#include <utility>

namespace {
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

bool IsPreference(const std::string& value) {
  return value == "auto" || value == "lowPower" || value == "highPerformance";
}

std::string Utf8(const wchar_t* value) {
  const int length = ::WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                          nullptr, nullptr);
  if (length <= 1) return std::string();
  std::string result(static_cast<size_t>(length), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), length, nullptr,
                        nullptr);
  result.pop_back();
  return result;
}

std::string Luid(const LUID& value) {
  std::ostringstream text;
  text << std::hex << std::setfill('0') << std::setw(8)
       << static_cast<uint32_t>(value.HighPart) << ':' << std::setw(8)
       << value.LowPart;
  return text.str();
}

std::string SystemError(const char* action, unsigned long code) {
  std::ostringstream text;
  text << action << " (0x" << std::hex << code << ')';
  return text.str();
}

std::string Trim(std::string value) {
  const auto first = value.find_first_not_of(" \r\n\t");
  if (first == std::string::npos) return std::string();
  const auto last = value.find_last_not_of(" \r\n\t");
  return value.substr(first, last - first + 1);
}
}  // namespace

GpuPreferences::GpuPreferences(bool background_preview)
    : background_preview_(background_preview) {
  if (background_preview_) return;
  PWSTR roaming_path = nullptr;
  const HRESULT result = ::SHGetKnownFolderPath(
      FOLDERID_RoamingAppData, KF_FLAG_DEFAULT, nullptr, &roaming_path);
  if (FAILED(result) || !roaming_path) {
    configuration_error_ = SystemError("Configuration path unavailable", result);
    if (roaming_path) ::CoTaskMemFree(roaming_path);
    return;
  }
  configuration_path_ = std::filesystem::path(roaming_path) / L"com.klpbbs" /
                        L"klpbbs_app" / L"pc_gpu_preference.txt";
  ::CoTaskMemFree(roaming_path);
  std::error_code error;
  const bool exists = std::filesystem::exists(*configuration_path_, error);
  if (error) {
    configuration_error_ = "Configuration file cannot be inspected";
    return;
  }
  if (!exists) return;
  std::ifstream input(*configuration_path_, std::ios::binary);
  char bytes[129] = {};
  input.read(bytes, sizeof(bytes));
  if (input.bad() || (!input.eof() && input.fail()) || input.gcount() > 128) {
    configuration_error_ = "Configuration file cannot be read";
    return;
  }
  const auto preference = Trim(std::string(bytes, static_cast<size_t>(input.gcount())));
  if (!IsPreference(preference)) {
    configuration_error_ = "Invalid saved GPU preference; automatic was used";
    return;
  }
  saved_preference_ = preference;
  startup_preference_ = preference;
}

GpuPreferences::~GpuPreferences() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

flutter::GpuPreference GpuPreferences::startup_preference() const {
  if (startup_preference_ == "lowPower") {
    return flutter::GpuPreference::LowPowerPreference;
  }
  if (startup_preference_ == "highPerformance") {
    return flutter::GpuPreference::HighPerformancePreference;
  }
  return flutter::GpuPreference::NoPreference;
}

EncodableMap GpuPreferences::Snapshot() const {
  EncodableList adapters;
  EncodableValue current_luid;
  EncodableValue current_name;
  std::string inventory_error;
  // Hidden QA uses only RAM plus the Dart mock channel; no actual GPU query.
  if (!background_preview_) {
    ComPtr<IDXGIFactory1> factory;
    const HRESULT factory_result = ::CreateDXGIFactory1(IID_PPV_ARGS(&factory));
    if (FAILED(factory_result)) {
      inventory_error = SystemError("GPU inventory unavailable", factory_result);
    } else {
      std::map<std::wstring, size_t> physical_adapters;
      std::map<std::string, size_t> logical_adapters;
      for (UINT index = 0;; ++index) {
        ComPtr<IDXGIAdapter1> adapter;
        const HRESULT next = factory->EnumAdapters1(index, &adapter);
        if (next == DXGI_ERROR_NOT_FOUND) break;
        if (FAILED(next)) {
          inventory_error = SystemError("GPU inventory incomplete", next);
          break;
        }
        DXGI_ADAPTER_DESC1 description = {};
        const HRESULT described = adapter->GetDesc1(&description);
        if (FAILED(described)) {
          inventory_error = SystemError("GPU description unavailable", described);
          continue;
        }
        if (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue;
        const auto logical_id = Luid(description.AdapterLuid);
        const auto identity = klpbbs_gpu::PhysicalIdentity(description.AdapterLuid);
        const auto logical_match = logical_adapters.find(logical_id);
        const auto physical_match = physical_adapters.find(identity);
        const bool same_physical = !identity.empty() && physical_match != physical_adapters.end();
        if (logical_match != logical_adapters.end() || same_physical) {
          const size_t group = logical_match != logical_adapters.end()
              ? logical_match->second : physical_match->second;
          auto& entry = std::get<EncodableMap>(adapters[group]);
          auto& aliases = std::get<EncodableList>(entry.at(EncodableValue("aliasLuids")));
          const EncodableValue alias(logical_id);
          if (std::find(aliases.begin(), aliases.end(), alias) == aliases.end()) aliases.push_back(alias);
          logical_adapters[logical_id] = group;
          continue;
        }
        const size_t group = adapters.size();
        logical_adapters[logical_id] = group;
        if (!identity.empty()) physical_adapters[identity] = group;
        adapters.emplace_back(EncodableMap{
            {EncodableValue("luid"), EncodableValue(logical_id)},
            {EncodableValue("aliasLuids"), EncodableValue(EncodableList{EncodableValue(logical_id)})},
            {EncodableValue("identitySource"), EncodableValue(identity.empty() ? "luid" : "physical")},
            {EncodableValue("name"), EncodableValue(Utf8(description.Description))},
            {EncodableValue("vendorId"), EncodableValue(static_cast<int64_t>(description.VendorId))},
            {EncodableValue("deviceId"), EncodableValue(static_cast<int64_t>(description.DeviceId))},
            {EncodableValue("dedicatedVideoMemory"), EncodableValue(static_cast<int64_t>(description.DedicatedVideoMemory))},
            {EncodableValue("sharedSystemMemory"), EncodableValue(static_cast<int64_t>(description.SharedSystemMemory))},
        });
      }
    }
    ComPtr<IDXGIAdapter> current;
    if (engine_ && engine_->GetGraphicsAdapter(current.GetAddressOf()) && current) {
      DXGI_ADAPTER_DESC description = {};
      if (SUCCEEDED(current->GetDesc(&description))) {
        current_luid = EncodableValue(Luid(description.AdapterLuid));
        current_name = EncodableValue(Utf8(description.Description));
      } else if (inventory_error.empty()) {
        inventory_error = "Current rendering adapter description unavailable";
      }
    } else if (inventory_error.empty()) {
      inventory_error = "Current rendering adapter unavailable";
    }
  }
  return EncodableMap{
      {EncodableValue("supported"), EncodableValue(true)},
      {EncodableValue("preview"), EncodableValue(background_preview_)},
      {EncodableValue("preference"), EncodableValue(saved_preference_)},
      {EncodableValue("startupPreference"), EncodableValue(startup_preference_)},
      {EncodableValue("nextStartRequiresRestart"), EncodableValue(saved_preference_ != startup_preference_)},
      {EncodableValue("canBindSpecificAdapter"), EncodableValue(false)},
      {EncodableValue("adapters"), EncodableValue(std::move(adapters))},
      {EncodableValue("currentLuid"), current_luid},
      {EncodableValue("currentName"), current_name},
      {EncodableValue("inventoryError"), EncodableValue(inventory_error)},
      {EncodableValue("configurationError"), EncodableValue(configuration_error_)},
  };
}

bool GpuPreferences::Save(const std::string& preference, std::string* error) {
  if (!IsPreference(preference)) {
    *error = "Unsupported GPU preference";
    return false;
  }
  if (background_preview_) {
    saved_preference_ = preference;
    return true;
  }
  if (!configuration_path_) {
    *error = "Configuration path unavailable";
    return false;
  }
  std::error_code filesystem_error;
  std::filesystem::create_directories(configuration_path_->parent_path(), filesystem_error);
  if (filesystem_error) {
    *error = "GPU configuration directory cannot be created";
    return false;
  }
  auto temporary = *configuration_path_;
  temporary += L".tmp-" + std::to_wstring(::GetCurrentProcessId()) + L"-" +
               std::to_wstring(::GetTickCount64());
  const HANDLE file = ::CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
                                   CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    *error = SystemError("GPU configuration cannot be written", ::GetLastError());
    return false;
  }
  const std::string bytes = preference + '\n';
  DWORD written = 0;
  bool success = ::WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                              &written, nullptr) && written == bytes.size();
  DWORD failure = success ? ERROR_SUCCESS : ::GetLastError();
  if (success && !::FlushFileBuffers(file)) {
    success = false;
    failure = ::GetLastError();
  }
  ::CloseHandle(file);
  if (success && !::MoveFileExW(temporary.c_str(), configuration_path_->c_str(),
                               MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    success = false;
    failure = ::GetLastError();
  }
  if (!success) {
    ::DeleteFileW(temporary.c_str());
    *error = SystemError("GPU configuration was not saved", failure);
    return false;
  }
  saved_preference_ = preference;
  configuration_error_.clear();
  return true;
}

void GpuPreferences::Register(flutter::FlutterEngine* engine) {
  engine_ = engine;
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "klpbbs/pc_gpu",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "getStatus") {
          result->Success(EncodableValue(Snapshot()));
        } else if (call.method_name() == "savePreference") {
          const auto* arguments = call.arguments();
          const auto* values = arguments ? std::get_if<EncodableMap>(arguments) : nullptr;
          const auto found = values ? values->find(EncodableValue("preference"))
                                    : EncodableMap::const_iterator();
          const auto* preference = values && found != values->end()
                                       ? std::get_if<std::string>(&found->second) : nullptr;
          std::string error;
          if (!preference || !IsPreference(*preference)) {
            result->Error("invalid_preference", "Choose auto, lowPower or highPerformance");
          } else if (!Save(*preference, &error)) {
            result->Error("configuration_write_failed", error);
          } else {
            result->Success(EncodableValue(Snapshot()));
          }
        } else if (call.method_name() == "openWindowsGraphicsSettings") {
          if (background_preview_) {
            result->Error("preview_blocked", "System settings are disabled in preview");
            return;
          }
          const auto opened = reinterpret_cast<INT_PTR>(::ShellExecuteW(
              nullptr, L"open", L"ms-settings:display-advancedgraphics", nullptr,
              nullptr, SW_SHOWNORMAL));
          if (opened <= 32) {
            result->Error("settings_open_failed", "Windows graphics settings could not be opened");
          } else {
            result->Success(EncodableValue(true));
          }
        } else {
          result->NotImplemented();
        }
      });
}
