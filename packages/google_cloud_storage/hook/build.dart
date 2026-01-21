import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    output.assets.code.add(
      CodeAsset(
        name: 'shim',
        file: Uri.file(
          // '/Users/bquinlan/dart/google-cloud-dart/packages/google_cloud_storage/bazel-bin/libshim_shared.dylib',
          '/Users/bquinlan/dart/google-cloud-dart/packages/google_cloud_storage/bazel-out/darwin_arm64-fastbuild/bin/libshim_shared.dylib',
        ),
        package: input.packageName,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}
