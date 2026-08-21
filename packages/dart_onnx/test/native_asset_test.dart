import 'package:dart_onnx/dart_onnx.dart';
import 'package:test/test.dart';

/// The package contract this fork did not have before: a consumer gets a real
/// ORT runtime without Homebrew, PATH, or another plugin happening to bundle
/// one. Running this test itself executes the build hook, resolves the bundled
/// code asset, and asks that runtime for its version.
void main() {
  test('the native-assets hook supplies ONNX Runtime', () {
    final env = DartONNX(loggingLevel: DartONNXLoggingLevel.warning);
    addTearDown(env.dispose);

    expect(env.ortVersion, startsWith('1.27.'));
  });
}
