import 'dart:convert';
import 'dart:io';

import 'package:comicollect/services/image_signature.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _catalogRelativePath = 'assets/catalog/bsp_catalog.json';
const _coversRelativePath = 'assets/catalog/covers';

Future<void> main(List<String> arguments) async {
  final appRoot = _findAppRoot();
  final command = arguments.firstOrNull ?? 'validate';
  try {
    switch (command) {
      case 'validate':
        final result = await CatalogPipeline(appRoot).validate();
        for (final warning in result.warnings) {
          stdout.writeln('WARNING: $warning');
        }
        for (final error in result.errors) {
          stderr.writeln('ERROR: $error');
        }
        stdout.writeln(
          'Catalog: ${result.issueCount} issues, '
          '${result.coverCount} local covers.',
        );
        if (result.errors.isNotEmpty) exitCode = 1;
        break;
      case 'refresh-signatures':
        final updated = await CatalogPipeline(appRoot).refreshSignatures();
        stdout.writeln('Updated visual signatures for $updated covers.');
        break;
      case 'import-cover':
        if (arguments.length < 3) {
          throw const FormatException(
            'Usage: import-cover <input-image> '
            '<assets/catalog/covers/edition/file.webp> [max-width]',
          );
        }
        final maxWidth = arguments.length >= 4 ? int.parse(arguments[3]) : 480;
        final output = await CatalogPipeline(appRoot).importCover(
          inputPath: arguments[1],
          outputAssetPath: arguments[2],
          maxWidth: maxWidth,
        );
        stdout.writeln(
          'Imported ${output.path} (${output.lengthSync()} bytes).',
        );
        break;
      default:
        throw FormatException('Unknown catalog command: $command');
    }
  } on Object catch (error) {
    stderr.writeln('Catalog pipeline failed: $error');
    exitCode = 64;
  }
}

class CatalogValidationResult {
  const CatalogValidationResult({
    required this.issueCount,
    required this.coverCount,
    required this.errors,
    required this.warnings,
  });

  final int issueCount;
  final int coverCount;
  final List<String> errors;
  final List<String> warnings;
}

class CatalogPipeline {
  CatalogPipeline(this.appRoot);

  final Directory appRoot;

  File get catalogFile => File(p.join(appRoot.path, _catalogRelativePath));
  Directory get coversDirectory =>
      Directory(p.join(appRoot.path, _coversRelativePath));

  Future<CatalogValidationResult> validate() async {
    final payload = await _loadCatalog();
    final errors = <String>[];
    final warnings = <String>[];
    final ids = <String>{};
    final issueKeys = <String>{};
    final referencedCovers = <String>{};
    final declaredEditions = (payload['editions'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
    final observedEditions = <String>{};
    final issues = _issues(payload);

    if (payload['schemaVersion'] != 1) {
      errors.add('Unsupported or missing schemaVersion.');
    }
    for (var index = 0; index < issues.length; index++) {
      final issue = issues[index];
      final label = 'issues[$index]';
      for (final field in const [
        'id',
        'sourceEdition',
        'series',
        'edition',
        'title',
        'publisher',
      ]) {
        if ((issue[field] as String? ?? '').trim().isEmpty) {
          errors.add('$label has an empty $field.');
        }
      }
      final id = issue['id'] as String? ?? '';
      if (!ids.add(id)) errors.add('Duplicate issue id: $id.');
      final sourceEdition = issue['sourceEdition'] as String? ?? '';
      observedEditions.add(sourceEdition);
      final number = (issue['number'] as num?)?.toInt();
      if (number == null || number <= 0) {
        errors.add('$id has an invalid number.');
      } else if (!issueKeys.add('$sourceEdition/$number')) {
        errors.add('Duplicate source edition/number: $sourceEdition/$number.');
      }

      final coverAsset = issue['coverAsset'] as String?;
      if (coverAsset == null || coverAsset.isEmpty) {
        if (issue['visualHash'] != null || issue['colorSignature'] != null) {
          errors.add('$id has a signature without a local cover.');
        }
        continue;
      }
      final normalizedAsset = _normalizeAssetPath(coverAsset);
      if (!normalizedAsset.startsWith('$_coversRelativePath/')) {
        errors.add('$id cover is outside the catalog cover directory.');
        continue;
      }
      if (!referencedCovers.add(normalizedAsset)) {
        errors.add('Cover is referenced more than once: $normalizedAsset.');
      }
      final cover = File(p.join(appRoot.path, normalizedAsset));
      if (!cover.existsSync()) {
        errors.add('$id is missing $normalizedAsset.');
        continue;
      }
      if (p.extension(cover.path).toLowerCase() != '.webp') {
        errors.add('$id cover is not WebP: $normalizedAsset.');
      }
      final image = img.decodeImage(await cover.readAsBytes());
      if (image == null) {
        errors.add('$id cover cannot be decoded: $normalizedAsset.');
        continue;
      }
      final expected = ImageSignatureExtractor.fromImage(image);
      if (issue['visualHash'] != expected.visualHash) {
        errors.add('$id visualHash does not match its bundled cover.');
      }
      final encodedColor = issue['colorSignature'] as String?;
      if (encodedColor == null ||
          !_sameBytes(_decodeBase64(encodedColor), expected.colorSignature)) {
        errors.add('$id colorSignature does not match its bundled cover.');
      }
    }

    if (!declaredEditions.containsAll(observedEditions) ||
        !observedEditions.containsAll(declaredEditions)) {
      errors.add(
        'Top-level editions do not match issue sourceEdition values: '
        'declared=$declaredEditions observed=$observedEditions.',
      );
    }

    final bundledCovers = coversDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.extension(file.path).toLowerCase() == '.webp')
        .map(
          (file) =>
              _normalizeAssetPath(p.relative(file.path, from: appRoot.path)),
        )
        .toSet();
    for (final orphan in bundledCovers.difference(referencedCovers)) {
      warnings.add('Unreferenced bundled cover: $orphan.');
    }

    return CatalogValidationResult(
      issueCount: issues.length,
      coverCount: bundledCovers.length,
      errors: errors,
      warnings: warnings,
    );
  }

  Future<int> refreshSignatures() async {
    final payload = await _loadCatalog();
    var updated = 0;
    for (final issue in _issues(payload)) {
      final coverAsset = issue['coverAsset'] as String?;
      if (coverAsset == null || coverAsset.isEmpty) continue;
      final cover = File(p.join(appRoot.path, _normalizeAssetPath(coverAsset)));
      final image = img.decodeImage(await cover.readAsBytes());
      if (image == null) throw FormatException('Cannot decode ${cover.path}.');
      final signature = ImageSignatureExtractor.fromImage(image);
      issue['visualHash'] = signature.visualHash;
      issue['colorSignature'] = base64Encode(signature.colorSignature);
      updated++;
    }
    const encoder = JsonEncoder.withIndent('  ');
    await catalogFile.writeAsString('${encoder.convert(payload)}\n');
    return updated;
  }

  Future<File> importCover({
    required String inputPath,
    required String outputAssetPath,
    required int maxWidth,
  }) async {
    if (maxWidth <= 0) {
      throw const FormatException('max-width must be positive.');
    }
    final normalizedOutput = _normalizeAssetPath(outputAssetPath);
    if (!normalizedOutput.startsWith('$_coversRelativePath/') ||
        p.extension(normalizedOutput).toLowerCase() != '.webp') {
      throw const FormatException(
        'Output must be a .webp path inside assets/catalog/covers/.',
      );
    }
    final input = File(inputPath);
    final decoded = img.decodeImage(await input.readAsBytes());
    if (decoded == null) throw FormatException('Cannot decode ${input.path}.');
    var image = img.bakeOrientation(decoded);
    if (image.width > maxWidth) {
      image = img.copyResize(
        image,
        width: maxWidth,
        interpolation: img.Interpolation.average,
      );
    }
    final output = File(p.join(appRoot.path, normalizedOutput));
    await output.parent.create(recursive: true);
    await output.writeAsBytes(img.encodeWebP(image), flush: true);
    return output;
  }

  Future<Map<String, dynamic>> _loadCatalog() async {
    final decoded = jsonDecode(await catalogFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Catalog root must be a JSON object.');
    }
    return decoded;
  }

  List<Map<String, dynamic>> _issues(Map<String, dynamic> payload) {
    final value = payload['issues'];
    if (value is! List<dynamic>) {
      throw const FormatException('Catalog issues must be a JSON array.');
    }
    return value
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException(
              'Every catalog issue must be an object.',
            );
          }
          return item;
        })
        .toList(growable: false);
  }
}

Directory _findAppRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (File(p.join(candidate.path, 'pubspec.yaml')).existsSync() &&
        File(p.join(candidate.path, _catalogRelativePath)).existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Run this command from the app directory or below it.');
    }
    candidate = parent;
  }
}

String _normalizeAssetPath(String value) =>
    p.posix.normalize(value.replaceAll('\\', '/'));

List<int> _decodeBase64(String value) {
  try {
    return base64Decode(value);
  } on FormatException {
    return const [];
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
