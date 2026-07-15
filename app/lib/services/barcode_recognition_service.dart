import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

abstract interface class BarcodeRecognitionService {
  Future<List<String>> recognize(InputImage image);
  Future<void> close();
}

class MlKitBarcodeRecognitionService implements BarcodeRecognitionService {
  MlKitBarcodeRecognitionService({BarcodeScanner? scanner})
    : _scanner =
          scanner ??
          BarcodeScanner(
            formats: const [
              BarcodeFormat.ean13,
              BarcodeFormat.ean8,
              BarcodeFormat.upca,
              BarcodeFormat.upce,
              BarcodeFormat.code128,
            ],
          );

  final BarcodeScanner _scanner;

  @override
  Future<List<String>> recognize(InputImage image) async {
    final barcodes = await _scanner.processImage(image);
    return barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> close() => _scanner.close();
}
