// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:universal_html/html.dart' as html;

import 'cipher.dart';

Future<DatabaseApi> flutterMatrixSdkDatabaseBuilder(String clientName) async {
  final stopwatch = Stopwatch()..start();
  try {
    final db = await _constructDatabase(clientName);
    Logs().i('[db] 打开成功 ${stopwatch.elapsedMilliseconds}ms');
    return db;
  } catch (e, s) {
    Logs().wtf('Unable to construct database!', e, s);

    try {
      // Send error notification:
      final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
      // We expect that the database cannot be open on iOS 2.8.0 due to that
      // the team ID has changed and te app can no longer access the database
      // key in the iOS keychain. This should be removed from 2.9.0 on.
      if (!PlatformInfos.isIOS) {
        ClientManager.sendInitNotification(l10n.initAppError, e.toString());
      }
    } catch (e, s) {
      Logs().e('Unable to send error notification', e, s);
    }

    // Qing v1.9.0：**不再直接删除数据库**
    //
    // 旧实现在这里 `delete()`，一旦是「密钥读不到 / 迁移中途失败」这类
    // 可恢复问题，就会把用户全部本地历史（含加密账号）静默销毁，随后
    // 触发全量重新同步 —— 正是升级后长时间卡在开屏的原因，而且不可逆。
    //
    // 现在改成重命名留档：数据库照样重建，但旧文件还在，事后能捞。
    if (!kIsWeb) {
      await _quarantineDatabase(await _getDatabasePath(clientName), 'open-failed');
    }

    // Try again
    return await _constructDatabase(clientName);
  }
}

/// 把有问题的数据库文件改名留档（而不是删除）
///
/// 保留最近 [keep] 份，避免反复启动把存储撑满。
Future<void> _quarantineDatabase(String path, String reason) async {
  final file = File(path);
  if (!await file.exists()) return;
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('-', '')
      .split('.')
      .first;
  final target = '$path.$reason-$stamp.bak';
  try {
    await file.rename(target);
    Logs().w('[db] 已将异常数据库留档为 $target（未删除）');
  } catch (e, s) {
    Logs().e('[db] 留档失败，保持原文件不动', e, s);
    rethrow;
  }

  // 只保留最近 2 份留档
  try {
    final dir = file.parent;
    final prefix = '${file.path.split(Platform.pathSeparator).last}.$reason-';
    final backups = await dir
        .list()
        .where((e) => e.path.split(Platform.pathSeparator).last.startsWith(prefix))
        .toList();
    backups.sort((a, b) => a.path.compareTo(b.path));
    while (backups.length > 2) {
      final oldest = backups.removeAt(0);
      await oldest.delete().catchError((_) => oldest);
    }
  } catch (e, s) {
    Logs().w('[db] 清理旧留档失败', e, s);
  }
}


Future<Directory?> getFileStorageLocation() async {
  try {
    late final Directory temporaryDirectory;
    if (PlatformInfos.isIOS) {
      final containerPath = await PathProviderFoundation().getContainerPath(
        appGroupIdentifier: 'group.im.fluffychat.app',
      );
      temporaryDirectory = Directory(containerPath!);
    } else if (PlatformInfos.isLinux) {
      temporaryDirectory = await getApplicationCacheDirectory();
    } else {
      temporaryDirectory = await getTemporaryDirectory();
    }
    return await Directory(
      join(temporaryDirectory.path, 'fluffychat_download_cache'),
    ).create(recursive: true);
  } on MissingPlatformDirectoryException catch (_) {
    Logs().w(
      'No temporary directory for file cache available on this platform.',
    );
  }
  return null;
}

Future<MatrixSdkDatabase> _constructDatabase(String clientName) async {
  if (kIsWeb) {
    html.window.navigator.storage?.persist();
    return await MatrixSdkDatabase.init(clientName);
  }

  final cipher = await getDatabaseCipher();

  final fileStorageLocation = await getFileStorageLocation();

  final path = await _getDatabasePath(clientName);

  // import the SQLite / SQLCipher shared objects / dynamic libraries
  final factory = createDatabaseFactoryFfi();

  // required for [getDatabasesPath]
  databaseFactory = factory;

  // migrate from potential previous SQLite database path to current one
  await _migrateLegacyLocation(path, clientName);

  // in case we got a cipher, we use the encryption helper
  // to manage SQLite encryption
  final helper = cipher == null
      ? null
      : SQfLiteEncryptionHelper(factory: factory, path: path, cipher: cipher);

  // check whether the DB is already encrypted and otherwise do so
  await helper?.ensureDatabaseFileEncrypted();

  final openDatabaseOptions = OpenDatabaseOptions(
    version: 1,
    // most important : apply encryption when opening the DB
    onConfigure: (db) =>
        helper?.applyPragmaKey(db, ensureIncrementalAutoVacuum: true),
  );

  late final Database database;
  try {
    database = await factory.openDatabase(path, options: openDatabaseOptions);
  } catch (e, s) {
    Logs().wtf('Unable to open database! Quarantine file and try again...', e, s);
    // Qing v1.9.0：留档而非删除，避免把用户历史静默销毁
    await _quarantineDatabase(path, 'corrupt');
    database = await openDatabase(path, options: openDatabaseOptions);
  }

  // v1.20.5 · 合入上游 v2.11.4（rc2.11.4-1）的修复：
  // 没有数据库加密（cipher == null）时不启用 secure storage。
  // 某些设备上 keystore 不可用会抛异常，进而掉进上面的 catch 分支
  // 把数据库留档重建（本地历史要重新同步一遍），加这层保护就不会走到那。
  final secureStorage =
      cipher == null ? null : FlutterSecureStorage(iOptions: iosOptions);

  return await MatrixSdkDatabase.init(
    clientName,
    database: database,
    maxFileSize: 1000 * 1000 * 10,
    fileStorageLocation: fileStorageLocation?.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
    secureStorage: secureStorage == null
        ? null
        : (
            read: (key) => secureStorage.read(key: key),
            write: (key, value) => secureStorage.write(key: key, value: value),
            delete: (key) => secureStorage.delete(key: key),
          ),
  );
}

Future<String> _getDatabaseDirectory() async {
  if (PlatformInfos.isIOS) {
    final containerPath = await PathProviderFoundation().getContainerPath(
      appGroupIdentifier: 'group.im.fluffychat.app',
    );
    if (containerPath == null) {
      Logs().w('No container path found for iOS app!');
      return (await getLibraryDirectory()).path;
    }
    return containerPath;
  }
  if (PlatformInfos.isMacOS) {
    return (await getLibraryDirectory()).path;
  }
  return (await getApplicationSupportDirectory()).path;
}

Future<String> _getDatabasePath(String clientName) async {
  final databaseDirectory = await _getDatabaseDirectory();

  return join(databaseDirectory, '$clientName.sqlite');
}

Future<void> _migrateLegacyLocation(
  String sqlFilePath,
  String clientName,
) async {
  final oldPath = PlatformInfos.isDesktop
      ? (await getApplicationSupportDirectory()).path
      : PlatformInfos.isIOS
      ? (await getLibraryDirectory()).path
      : await getDatabasesPath();

  final oldFilePath = join(oldPath, '$clientName.sqlite');
  if (oldFilePath == sqlFilePath) return;

  final maybeOldFile = File(oldFilePath);
  if (!await maybeOldFile.exists()) return;

  // Qing v1.9.0：目标库已存在 → 之前早就迁移过了，旧文件只是残留。
  // 旧实现不管目标是否存在都会 `copy + delete`，一旦 delete 失败（权限、
  // 文件被占用），**每次冷启动都要整库复制一遍**，大库上这是几秒级阻塞。
  final target = File(sqlFilePath);
  if (await target.exists()) {
    Logs().i(
      'Legacy database target exists, drop leftover "$oldFilePath" without copying',
    );
    try {
      await maybeOldFile.delete();
    } catch (e, s) {
      Logs().w('Unable to delete leftover legacy database', e, s);
    }
    return;
  }

  Logs().i(
    'Migrate legacy location for database from "$oldFilePath" to "$sqlFilePath"',
  );
  await maybeOldFile.copy(sqlFilePath);
  try {
    await maybeOldFile.delete();
  } catch (e, s) {
    Logs().w('Unable to delete migrated legacy database', e, s);
  }
}
