import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'account_backend.dart';

/// Each base64 chunk is at most 256 KiB, below Firestore's document limit.
abstract final class CloudBackupCodec {
  static const chunkBytes = 192 * 1024;
  static const maxBytes = 20 * 1024 * 1024;
  static const maxChunks = (maxBytes + chunkBytes - 1) ~/ chunkBytes;

  static List<String> split(String archive) {
    final bytes = utf8.encode(archive);
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const AccountFailure('backup-too-large');
    }
    return [
      for (var start = 0; start < bytes.length; start += chunkBytes)
        base64Encode(
          bytes.sublist(start, (start + chunkBytes).clamp(0, bytes.length)),
        ),
    ];
  }

  static String checksum(String archive) =>
      sha256.convert(utf8.encode(archive)).toString();

  static String join(
    List<String> chunks, {
    required int byteLength,
    required String expectedChecksum,
  }) {
    if (byteLength <= 0 ||
        byteLength > maxBytes ||
        chunks.isEmpty ||
        chunks.length > maxChunks ||
        chunks.length != (byteLength + chunkBytes - 1) ~/ chunkBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedChecksum)) {
      throw const AccountFailure('backup-invalid');
    }
    try {
      final bytes = BytesBuilder(copy: false);
      for (var index = 0; index < chunks.length; index++) {
        final chunk = chunks[index];
        if (chunk.length > 262144) throw const FormatException();
        final decoded = base64Decode(chunk);
        final expectedLength = index == chunks.length - 1
            ? byteLength - index * chunkBytes
            : chunkBytes;
        if (decoded.length != expectedLength) throw const FormatException();
        bytes.add(decoded);
      }
      final data = bytes.takeBytes();
      if (data.length != byteLength ||
          sha256.convert(data).toString() != expectedChecksum) {
        throw const FormatException();
      }
      return utf8.decode(data, allowMalformed: false);
    } catch (_) {
      throw const AccountFailure('backup-invalid');
    }
  }
}
