import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/sync/attachment_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

AttachmentData _attachment(String storageKey, {int seed = 0}) => AttachmentData(
  id: 'id-$seed',
  fileName: 'file-$seed.bin',
  storageKey: storageKey,
  size: 100 + seed,
  sha256: 'hash-$seed',
  createdAt: DateTime.utc(2026, 8, 20),
);

void main() {
  test('keys follow the versioned attachment layout', () {
    expect(attachmentFileKey('abc'), 'attachments/v1/abc');
    expect(attachmentManifestKey, 'attachments/manifest.json');
  });

  test('build drops unpersisted attachments and sorts deterministically', () {
    final manifest = AttachmentManifest.build([
      _attachment('b', seed: 2),
      _attachment('', seed: 3),
      _attachment('a', seed: 1),
    ]);

    expect(manifest.entries.map((entry) => entry.storageKey), ['a', 'b']);
    expect(manifest.contains('a'), isTrue);
    expect(manifest.contains('missing'), isFalse);
  });

  test('bytes are deterministic for the same attachment set', () {
    final first = AttachmentManifest.build([
      _attachment('b', seed: 2),
      _attachment('a', seed: 1),
    ]).toBytes();
    final second = AttachmentManifest.build([
      _attachment('a', seed: 1),
      _attachment('b', seed: 2),
    ]).toBytes();

    expect(first, second);
  });

  test('roundtrips through bytes and back', () {
    final manifest = AttachmentManifest.build([
      _attachment('b', seed: 2),
      _attachment('a', seed: 1),
    ]);

    final decoded = AttachmentManifest.fromBytes(manifest.toBytes());

    expect(decoded.entries.length, 2);
    expect(decoded.entries[0].storageKey, 'a');
    expect(decoded.entries[0].sha256, 'hash-1');
    expect(decoded.entries[0].size, 101);
    expect(decoded.contains('b'), isTrue);
  });

  test('rejects unsupported format versions', () {
    final bytes = AttachmentManifest.build([
      _attachment('a', seed: 1),
    ]).toBytes();
    // 篡改 formatVersion：把版本号从 1 改成 2 需要重新构造 JSON，
    // 这里直接用不合规 payload 验证拒绝路径。
    const invalid = '{"formatVersion":99,"attachments":[]}';

    expect(
      () => AttachmentManifest.fromBytes(invalid.codeUnits),
      throwsFormatException,
    );
    expect(bytes, isNotEmpty);
  });

  test('rejects malformed documents', () {
    expect(
      () => AttachmentManifest.fromBytes('not json'.codeUnits),
      throwsFormatException,
    );
    expect(
      () => AttachmentManifest.fromBytes('{"formatVersion":1}'.codeUnits),
      throwsFormatException,
    );
    expect(
      () => AttachmentManifest.fromBytes(
        '{"formatVersion":1,"attachments":[{}]}'.codeUnits,
      ),
      throwsFormatException,
    );
  });
}
