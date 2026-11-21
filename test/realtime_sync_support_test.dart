import 'dart:io';

import 'package:ds_easy_db_firebase_realtime/ds_easy_db_firebase_realtime.dart';
import 'package:ds_sync_contract/ds_sync_contract.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RealtimeCursor', () {
    test('round-trips through its persisted string form', () {
      const cursor = RealtimeCursor(updatedAtMillis: 1780000000000, key: 'k1');

      final decoded = RealtimeCursor.decode(cursor.encode())!;
      expect(decoded.updatedAtMillis, cursor.updatedAtMillis);
      expect(decoded.key, cursor.key);
    });

    test('exposes the timestamp as UTC for anchors', () {
      final cursor = RealtimeCursor(
        updatedAtMillis: DateTime.utc(2026, 6, 1).millisecondsSinceEpoch,
        key: 'k',
      );

      expect(cursor.updatedAt, DateTime.utc(2026, 6, 1));
      expect(cursor.updatedAt.isUtc, isTrue);
    });

    test('keeps the key, so a timestamp tie has a tie-breaker', () {
      const first = RealtimeCursor(updatedAtMillis: 100, key: 'a');
      const second = RealtimeCursor(updatedAtMillis: 100, key: 'b');

      expect(first.encode(), isNot(second.encode()));
    });

    test('unparseable input restarts from the beginning instead of throwing',
        () {
      expect(RealtimeCursor.decode(null), isNull);
      expect(RealtimeCursor.decode('no-separator'), isNull);
      expect(RealtimeCursor.decode('/only-key'), isNull);
      expect(RealtimeCursor.decode('123/'), isNull);
      expect(RealtimeCursor.decode(7), isNull);
    });
  });

  group('error mapping', () {
    SyncErrorKind kindOf(String code) => mapRealtimeError(
          FirebaseException(plugin: 'firebase_database', code: code),
          StackTrace.current,
        ).kind;

    test(
        'an unreachable backend is transient, so no connectivity plugin is '
        'needed', () {
      expect(kindOf('disconnected'), SyncErrorKind.transient);
      expect(kindOf('network-error'), SyncErrorKind.transient);
      expect(
        mapRealtimeError(
          const SocketException('no route to host'),
          StackTrace.current,
        ).kind,
        SyncErrorKind.transient,
      );
    });

    test('auth failures are surfaced, not retried blindly', () {
      expect(kindOf('permission-denied'), SyncErrorKind.unauthorized);
      expect(kindOf('expired-token'), SyncErrorKind.unauthorized);
    });

    test('an unknown code errs towards retrying', () {
      expect(kindOf('brand-new-code'), SyncErrorKind.transient);
    });

    test('the original exception is preserved for logging', () {
      final original =
          FirebaseException(plugin: 'firebase_database', code: 'disconnected');
      final mapped = mapRealtimeError(original, StackTrace.current);

      expect(mapped.cause, same(original));
      expect(mapped.message, contains('disconnected'));
    });

    test('an already-normalised error passes through untouched', () {
      const original = SyncError(SyncErrorKind.paymentRequired);
      expect(mapRealtimeError(original, StackTrace.current), same(original));
    });
  });

  group('document normalisation', () {
    test('re-keys the loosely typed map the backend returns', () {
      final document = asDocument(<Object?, Object?>{
        'title': 'x',
        'updatedAt': 1780000000000,
      });

      expect(document, isA<Map<String, dynamic>>());
      expect(document!['title'], 'x');
    });

    test('nested maps are re-keyed too, not only the top level', () {
      final document = asDocument(<Object?, Object?>{
        'address': <Object?, Object?>{
          'geo': <Object?, Object?>{'lat': 1.0},
        },
        'tags': <Object?>[
          <Object?, Object?>{'name': 'a'},
        ],
      })!;

      expect(document['address'], isA<Map<String, dynamic>>());
      expect(document['address']['geo'], isA<Map<String, dynamic>>());
      expect((document['tags'] as List).single, isA<Map<String, dynamic>>());
    });

    test('a non-map child is skipped rather than crashing a pull', () {
      expect(asDocument('just a string'), isNull);
      expect(asDocument(null), isNull);
    });
  });

  group('anchors', () {
    test('reads the server timestamp millis as the comparison anchor', () {
      final anchor = realtimeAnchorFrom(
        {'updatedAt': DateTime.utc(2026, 6, 1).millisecondsSinceEpoch},
        'updatedAt',
      );

      expect(anchor.updatedAt, DateTime.utc(2026, 6, 1));
    });

    test('a child without the field yields an empty anchor', () {
      expect(realtimeAnchorFrom({'title': 'x'}, 'updatedAt').isEmpty, isTrue);
    });
  });

  group('capabilities', () {
    test('declares timestamps, delta pull and atomic multi-path writes', () {
      final capabilities = RealtimeSyncAdapter().capabilities;

      expect(capabilities.supportsTimestamps, isTrue);
      expect(capabilities.supportsDeltaPull, isTrue);
      expect(capabilities.supportsBatchWrite, isTrue);
      expect(capabilities.supportsVersioning, isFalse);
    });

    test('delta deletes require a remote soft-delete flag', () {
      expect(RealtimeSyncAdapter().capabilities.supportsDeltaDeletes, isFalse);
      expect(
        RealtimeSyncAdapter(deletedField: 'deleted')
            .capabilities
            .supportsDeltaDeletes,
        isTrue,
      );
    });
  });
}
