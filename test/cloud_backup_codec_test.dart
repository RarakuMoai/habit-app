import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/account_backend.dart';
import 'package:habit_app/utils/cloud_backup_codec.dart';

void main() {
  test('multibyte text round trips across exact chunk boundaries', () {
    final archive = '${'a' * (CloudBackupCodec.chunkBytes - 1)}兔咪🐰家庭紀錄';
    final chunks = CloudBackupCodec.split(archive);
    expect(chunks.length, 2);
    expect(chunks.every((chunk) => chunk.length <= 262144), isTrue);
    expect(
      CloudBackupCodec.join(
        chunks,
        byteLength: utf8.encode(archive).length,
        expectedChecksum: CloudBackupCodec.checksum(archive),
      ),
      archive,
    );
  });
  test('transport rejects a missing, reordered or modified chunk', () {
    final archive = '${'a' * CloudBackupCodec.chunkBytes}rest';
    final chunks = CloudBackupCodec.split(archive);
    final length = utf8.encode(archive).length;
    final checksum = CloudBackupCodec.checksum(archive);
    for (final invalid in [
      chunks.sublist(0, 1),
      chunks.reversed.toList(),
      [chunks.first, base64Encode(utf8.encode('evil'))],
    ]) {
      expect(
        () => CloudBackupCodec.join(
          invalid,
          byteLength: length,
          expectedChecksum: checksum,
        ),
        throwsA(isA<AccountFailure>()),
      );
    }
  });
  test('size cap is applied before allocating the reconstructed payload', () {
    expect(
      () => CloudBackupCodec.join(
        ['YQ=='],
        byteLength: CloudBackupCodec.maxBytes + 1,
        expectedChecksum: 'a' * 64,
      ),
      throwsA(isA<AccountFailure>()),
    );
    expect(() => CloudBackupCodec.split(''), throwsA(isA<AccountFailure>()));
  });
  test('exactly one full chunk is valid', () {
    final archive = 'a' * CloudBackupCodec.chunkBytes;
    expect(
      CloudBackupCodec.join(
        CloudBackupCodec.split(archive),
        byteLength: archive.length,
        expectedChecksum: CloudBackupCodec.checksum(archive),
      ),
      archive,
    );
  });
}
