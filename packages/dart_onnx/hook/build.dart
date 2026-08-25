import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

const _ortVersion = '1.27.0';
const _assetName = 'src/ort_library.dart';

final class _Artifact {
  const _Artifact({
    required this.url,
    required this.sha256,
    required this.entrySuffix,
  });

  final String url;
  final String sha256;
  final String entrySuffix;

  bool get isZip =>
      Uri.parse(url).path.endsWith('.zip') ||
      Uri.parse(url).path.endsWith('.aar');
}

const _artifacts = <String, _Artifact>{
  'android-arm': _Artifact(
    url:
        'https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/'
        'onnxruntime-android/$_ortVersion/'
        'onnxruntime-android-$_ortVersion.aar',
    sha256: '077dec5e2d821234c7dc0aba584bec8f999854b546c754cab93a90741c56fbeb',
    entrySuffix: 'jni/armeabi-v7a/libonnxruntime.so',
  ),
  'android-arm64': _Artifact(
    url:
        'https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/'
        'onnxruntime-android/$_ortVersion/'
        'onnxruntime-android-$_ortVersion.aar',
    sha256: '077dec5e2d821234c7dc0aba584bec8f999854b546c754cab93a90741c56fbeb',
    entrySuffix: 'jni/arm64-v8a/libonnxruntime.so',
  ),
  'android-x64': _Artifact(
    url:
        'https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/'
        'onnxruntime-android/$_ortVersion/'
        'onnxruntime-android-$_ortVersion.aar',
    sha256: '077dec5e2d821234c7dc0aba584bec8f999854b546c754cab93a90741c56fbeb',
    entrySuffix: 'jni/x86_64/libonnxruntime.so',
  ),
  'linux-arm64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-linux-aarch64-$_ortVersion.tgz',
    sha256: '3e4d83ac06924a32a07b6d7f91ce6f852876153fc0bbdf931bf517a140bfbe48',
    entrySuffix: 'lib/libonnxruntime.so.$_ortVersion',
  ),
  'linux-x64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-linux-x64-$_ortVersion.tgz',
    sha256: '547e40a48f1fe73e3f812d7c88a948612c23f896b91e4e2ee1e232d7b468246f',
    entrySuffix: 'lib/libonnxruntime.so.$_ortVersion',
  ),
  'macos-arm64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-osx-arm64-$_ortVersion.tgz',
    sha256: '545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a',
    entrySuffix: 'lib/libonnxruntime.$_ortVersion.dylib',
  ),
  'windows-arm64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-win-arm64-$_ortVersion.zip',
    sha256: 'a32f2650575b3c20df462e337519fd1cc4105356130d11dba9771c6f374d952f',
    entrySuffix: 'lib/onnxruntime.dll',
  ),
  'windows-x64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-win-x64-$_ortVersion.zip',
    sha256: 'c5c81710938e68079ff1a192b04897faabe4b43830d48f39f27ecd4e16138bfc',
    entrySuffix: 'lib/onnxruntime.dll',
  ),
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final external = input.userDefines['external_platforms'];
    if (external is List && external.contains(os.name)) return;
    if (os == OS.iOS) {
      // iOS builds ORT statically through the app/plugin toolchain and FFI
      // resolves it with DynamicLibrary.process(). Emitting no code asset here
      // preserves that supported path; FAILING the hook made every iOS app
      // unbuildable even when it never used generic ONNX inference.
      return;
    }
    final key = '${os.name}-${input.config.code.targetArchitecture.name}';
    final artifact = _artifacts[key];
    if (artifact == null) {
      throw UnsupportedError(
        'No dart_onnx ONNX Runtime artifact for $key. Supported: '
        '${_artifacts.keys.join(', ')}.',
      );
    }

    final name = os.dylibFileName('onnxruntime');
    final cached = await _cachedLibrary(artifact, name);
    final out = File.fromUri(input.outputDirectory.resolve(name));
    await out.parent.create(recursive: true);
    await cached.copy(out.path);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: out.uri,
      ),
    );
    output.dependencies.add(input.packageRoot.resolve('hook/build.dart'));
  });
}

Future<File> _cachedLibrary(_Artifact artifact, String outputName) async {
  final entryKey = sha256
      .convert(artifact.entrySuffix.codeUnits)
      .toString()
      .substring(0, 16);
  final root = Directory(
    p.join(_cacheRoot().path, 'artifacts', artifact.sha256, entryKey),
  );
  final library = File(p.join(root.path, outputName));
  if (await library.exists()) return library;
  await root.create(recursive: true);

  final lock = await File(
    p.join(root.path, '.lock'),
  ).open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    if (await library.exists()) return library;
    final archive = File(
      p.join(root.path, artifact.isZip ? 'artifact.zip' : 'artifact.tgz'),
    );
    await _download(artifact, archive);
    await _extract(artifact, archive, library);
    return library;
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<void> _download(_Artifact artifact, File archive) async {
  if (await archive.exists() && await _digest(archive) == artifact.sha256) {
    return;
  }
  if (await archive.exists()) await archive.delete();
  final partial = File('${archive.path}.partial');
  if (await partial.exists()) await partial.delete();

  stderr.writeln('dart_onnx: downloading ${artifact.url}');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(artifact.url));
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'dart-onnx-native-assets/1',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Download failed: HTTP ${response.statusCode}');
    }
    await response.pipe(partial.openWrite());
  } finally {
    client.close(force: true);
  }

  final actual = await _digest(partial);
  if (actual != artifact.sha256) {
    await partial.delete();
    throw StateError(
      'SHA-256 mismatch for ${artifact.url}: expected ${artifact.sha256}, '
      'got $actual.',
    );
  }
  await partial.rename(archive.path);
}

Future<void> _extract(_Artifact artifact, File archive, File output) async {
  final bytes = await archive.readAsBytes();
  final decoded = artifact.isZip
      ? ZipDecoder().decodeBytes(bytes, verify: true)
      : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  final matches = decoded.files
      .where(
        (e) =>
            e.isFile &&
            e.name.replaceAll('\\', '/').endsWith(artifact.entrySuffix),
      )
      .toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected one ${artifact.entrySuffix}, found '
      '${matches.map((e) => e.name).toList()}.',
    );
  }
  final extracted = matches.single.readBytes();
  if (extracted == null || extracted.isEmpty) {
    throw StateError('Extracted ONNX Runtime library is empty.');
  }
  final partial = File('${output.path}.partial');
  await partial.writeAsBytes(extracted, flush: true);
  await partial.rename(output.path);
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Directory _cacheRoot() {
  final xdg = Platform.environment['XDG_CACHE_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    return Directory(p.join(xdg, 'dart_onnx'));
  }
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      (throw StateError('HOME and USERPROFILE are unset.'));
  return Directory(p.join(home, '.cache', 'dart_onnx'));
}
