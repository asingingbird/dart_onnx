## 0.1.1

- Fixed an issue where model paths were not correctly parsed on Windows.

## 0.1.0

- Initial release.
- Added ONNX Runtime Dart FFI bindings.
- Added `DartONNXSession` and `DartONNXTensor` with optimized memory management.
- Added support for configuring Execution Providers (CoreML, NNAPI, etc.) with automatic fallbacks.
- Added an example demonstrating inference with a Hugging Face ONNX model (SmolLM2-135M).
- Added test suites.
## 0.2.0

- Bundle ONNX Runtime 1.27.0 with a SHA-256-verified native-assets build hook
  on macOS, Android, Linux, and Windows.
- Keep `DART_ONNX_LIB_PATH` as an explicit development override.
- Stop depending on another plugin or a system package to provide ORT.
