#ifndef RUNNER_GPU_PREFERENCES_H_
#define RUNNER_GPU_PREFERENCES_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <filesystem>
#include <memory>
#include <optional>
#include <string>

// App-local engine preference, unrelated to forum accounts or system registry.
// Preview processes never resolve or access the normal configuration path.
class GpuPreferences {
 public:
  explicit GpuPreferences(bool background_preview);
  ~GpuPreferences();
  flutter::GpuPreference startup_preference() const;
  void Register(flutter::FlutterEngine* engine);

 private:
  flutter::EncodableMap Snapshot() const;
  bool Save(const std::string& preference, std::string* error);
  bool background_preview_;
  std::string saved_preference_ = "auto";
  std::string startup_preference_ = "auto";
  std::string configuration_error_;
  std::optional<std::filesystem::path> configuration_path_;
  flutter::FlutterEngine* engine_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_GPU_PREFERENCES_H_
