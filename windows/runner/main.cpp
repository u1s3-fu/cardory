#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include <cstdlib>
#include <cwchar>
#include <iterator>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kEngineSwitchCount[] = L"FLUTTER_ENGINE_SWITCHES";
constexpr wchar_t kSoftwareRenderingSwitch[] =
    L"enable-software-rendering=true";

void EnableSoftwareRendering() {
  wchar_t count_buffer[16] = {};
  const DWORD count_length = GetEnvironmentVariableW(
      kEngineSwitchCount, count_buffer,
      static_cast<DWORD>(std::size(count_buffer)));
  int switch_count = count_length > 0 ? _wtoi(count_buffer) : 0;
  if (switch_count < 0) {
    switch_count = 0;
  }

  for (int index = 1; index <= switch_count; ++index) {
    const std::wstring name =
        L"FLUTTER_ENGINE_SWITCH_" + std::to_wstring(index);
    wchar_t value[128] = {};
    if (GetEnvironmentVariableW(name.c_str(), value,
                                static_cast<DWORD>(std::size(value))) > 0 &&
        _wcsicmp(value, kSoftwareRenderingSwitch) == 0) {
      return;
    }
  }

  const int next_index = switch_count + 1;
  const std::wstring switch_name =
      L"FLUTTER_ENGINE_SWITCH_" + std::to_wstring(next_index);
  SetEnvironmentVariableW(switch_name.c_str(), kSoftwareRenderingSwitch);
  SetEnvironmentVariableW(kEngineSwitchCount,
                          std::to_wstring(next_index).c_str());
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ::SetCurrentProcessExplicitAppUserModelID(L"com.cardory.productivity");

  // Cardory is a desktop utility. Software rendering prevents GPU monitoring
  // tools from classifying its persistent Flutter surface as a game.
  EnableSoftwareRendering();

  flutter::DartProject project(L"data");
  project.set_gpu_preference(flutter::GpuPreference::LowPowerPreference);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(
          L"\u677F\u8BB0 Cardory - \u9879\u76EE\u770B\u677F\u4E0E\u5F85\u529E\u7BA1\u7406",
          origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
