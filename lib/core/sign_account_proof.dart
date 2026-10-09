import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Notification and daily proofs survive credential rotation for the same UID.
/// The live request still uses its credential fingerprint to reject old replies.
class SignAccountProof {
  SignAccountProof._();

  static String scope(Uri forum, int uid) {
    if (uid <= 0) throw ArgumentError.value(uid, 'uid');
    return 'account:${sha256.convert(utf8.encode('${forum.origin}|$uid'))}';
  }

  static bool shouldNotify({
    required bool submittedSuccessfully,
    required bool enabled,
    required String today,
    required String lastNotifiedDay,
  }) =>
      submittedSuccessfully && enabled && lastNotifiedDay != today;
}
