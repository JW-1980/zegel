cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply standard settings to the executable.
apply_standard_settings(${BINARY_NAME})

# Add dependency libraries. Enable MSVC warning C4099 to warn if an unresolved reference uses /Z7 instead of /Zi.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be modified.
add_dependencies(${BINARY_NAME} flutter_assemble)
