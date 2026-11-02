// 备份文件加解密：PBKDF2-SHA256 派生 64 字节（前 32 为 AES-256 密钥，
// 后 32 为 HMAC-SHA256 密钥），AES-256-CBC + PKCS7 加密整个备份 JSON，
// HMAC 提供完整性校验（密码错误 / 文件被篡改都会在解密前被拦截）。
// 选 pointycastle 而非上层封装包：API 稳定可控，且 crypto 已是项目依赖。

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// PBKDF2 迭代次数：移动端单次派生约几百毫秒，安全与体验平衡。
const int kBackupKdfIterations = 60000;

/// 备份加密异常：统一按「密码错误或文件已损坏」提示，不区分细节（防枚举）。
class BackupCryptoException implements Exception {
  final String message;
  const BackupCryptoException([this.message = '密码错误或文件已损坏']);
  @override
  String toString() => message;
}

/// 加密备份的 payload 结构（自描述，便于未来算法升级）。
class EncryptedPayload {
  final String salt; // base64
  final String iv; // base64
  final String ciphertext; // base64
  final String hmac; // hex，HMAC-SHA256(salt + iv + ciphertext)

  const EncryptedPayload({
    required this.salt,
    required this.iv,
    required this.ciphertext,
    required this.hmac,
  });

  Map<String, dynamic> toJson() => {
        'kdf': 'PBKDF2-SHA256',
        'iterations': kBackupKdfIterations,
        'cipher': 'AES-256-CBC',
        'salt': salt,
        'iv': iv,
        'ciphertext': ciphertext,
        'hmac': hmac,
      };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    final salt = json['salt'];
    final iv = json['iv'];
    final ciphertext = json['ciphertext'];
    final hmac = json['hmac'];
    if (salt is! String || salt.isEmpty ||
        iv is! String || iv.isEmpty ||
        ciphertext is! String || ciphertext.isEmpty ||
        hmac is! String || hmac.isEmpty) {
      throw const BackupCryptoException();
    }
    return EncryptedPayload(
        salt: salt, iv: iv, ciphertext: ciphertext, hmac: hmac);
  }
}

class _DerivedKeys {
  final Uint8List encKey;
  final Uint8List macKey;
  const _DerivedKeys(this.encKey, this.macKey);
}

_DerivedKeys _deriveKeys(String password, Uint8List salt) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, kBackupKdfIterations, 64));
  final derived = derivator.process(Uint8List.fromList(utf8.encode(password)));
  return _DerivedKeys(
    Uint8List.sublistView(derived, 0, 32),
    Uint8List.sublistView(derived, 32, 64),
  );
}

String _hmacHex(Uint8List macKey, List<int> salt, List<int> iv, Uint8List ct) {
  final mac = crypto.Hmac(crypto.sha256, macKey);
  return mac.convert([...salt, ...iv, ...ct]).toString();
}

Uint8List _runAesCbc(Uint8List data, Uint8List key, Uint8List iv,
    {required bool encrypt}) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(
      encrypt,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );
  return cipher.process(data);
}

/// 明文备份 JSON → 加密 payload。
EncryptedPayload encryptBackupJson(String plainJson, String password) {
  final rnd = Random.secure();
  final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => rnd.nextInt(256)));
  final iv = Uint8List.fromList(
      List<int>.generate(16, (_) => rnd.nextInt(256)));
  final keys = _deriveKeys(password, salt);
  final ct = _runAesCbc(
      Uint8List.fromList(utf8.encode(plainJson)), keys.encKey, iv,
      encrypt: true);
  return EncryptedPayload(
    salt: base64Encode(salt),
    iv: base64Encode(iv),
    ciphertext: base64Encode(ct),
    hmac: _hmacHex(keys.macKey, salt, iv, ct),
  );
}

/// 加密 payload → 明文备份 JSON；HMAC 不匹配或解密失败抛 [BackupCryptoException]。
String decryptBackupJson(EncryptedPayload payload, String password) {
  try {
    final salt = base64Decode(payload.salt);
    final iv = base64Decode(payload.iv);
    final ct = base64Decode(payload.ciphertext);
    final keys = _deriveKeys(password, salt);
    final expect = _hmacHex(keys.macKey, salt, iv, ct);
    if (!_constantTimeEquals(expect, payload.hmac)) {
      throw const BackupCryptoException();
    }
    return utf8.decode(_runAesCbc(ct, keys.encKey, iv, encrypt: false));
  } on BackupCryptoException {
    rethrow;
  } catch (_) {
    // 格式损坏（base64 非法 / PKCS7 padding 错误等）。
    throw const BackupCryptoException();
  }
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
