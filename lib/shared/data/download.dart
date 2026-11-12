import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

/// A utility class for downloading files to the device.
abstract final class FileDownloader {
  /// Allows the user to pick a directory for downloading files.
  static Future<String?> pickDirectory({String? initial}) async {
    if (Platform.isAndroid) {
      if (initial?.contains('/storage/emulated/') ?? false) {
        initial = null;
      }

      final dir = await SafUtil().pickDirectory(
        initialUri: initial,
        writePermission: true,
        persistablePermission: true,
      );
      return dir?.uri;
    } else {
      return FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose a folder',
        initialDirectory: initial,
      );
    }
  }

  /// Releases permissions to a previously selected directory.
  static Future<void> forgetDirectory(String? directory) async {
    if (Platform.isAndroid && directory != null) {
      // Not implemented
    }
  }

  /// Downloads a file to the specified directory.
  static Future<void> downloadFile({
    required File file,
    required String? directory,
    String? folderName,
    String? fileName,
    void Function(String dir)? onDirectoryChanged,
  }) async {
    try {
      if (Platform.isIOS) {
        throw UnsupportedError(
          'Generic file downloading is not supported on iOS',
        );
      } else if (Platform.isAndroid) {
        if (directory?.contains('/storage/emulated/') ?? false) {
          directory = null;
        }

        String baseTarget;
        if (directory == null ||
            !await SafUtil().hasPersistedPermission(
              directory,
              checkWrite: true,
            )) {
          baseTarget = await _throwOnNull(
            pickDirectory(initial: directory),
            'No directory was selected.',
          );
          onDirectoryChanged?.call(baseTarget);
        } else {
          baseTarget = directory;
        }

        String saveTarget = baseTarget;
        final segments = folderName
                ?.split(RegExp(r'[\\/]'))
                .where((s) => s.trim().isNotEmpty)
                .toList() ??
            const [];
        if (segments.isNotEmpty) {
          try {
            final targetDir = await SafUtil().mkdirp(baseTarget, segments);
            saveTarget = targetDir.uri;
          } on Exception {
            // can't create app specific sub-folder, fall back to baseTarget
          }
        }

        final safStream = SafStream();
        final mimeType =
            lookupMimeType(fileName ?? basename(file.path)) ??
            'application/octet-stream';
        await safStream.pasteLocalFile(
          file.path,
          saveTarget,
          fileName ?? basename(file.path),
          mimeType,
          overwrite: true,
        );
        await MediaScanner.loadMedia(path: saveTarget);
      } else {
        String directoryPath =
            directory ??
            await _throwOnNull(pickDirectory(), 'No directory was selected.');

        onDirectoryChanged?.call(directoryPath);

        final segments = folderName
                ?.split(RegExp(r'[\\/]'))
                .where((s) => s.trim().isNotEmpty)
                .toList() ??
            const [];
        if (segments.isNotEmpty) {
          directoryPath = joinAll([directoryPath, ...segments]);
        }

        final targetDir = Directory(directoryPath);
        if (!targetDir.existsSync()) {
          await targetDir.create(recursive: true);
        }

        final targetFile = File(
          join(directoryPath, fileName ?? basename(file.path)),
        );
        await targetFile.writeAsBytes(await file.readAsBytes());
      }
    } on Exception catch (e) {
      throw FileDownloadException.from(e);
    }
  }

  /// Downloads an image file to the device's gallery or a specified directory.
  static Future<void> downloadImage({
    required File file,
    required String? directory,
    String? folderName,
    String? fileName,
    void Function(String dir)? onDirectoryChanged,
  }) async {
    if (Platform.isIOS) {
      await ImageGallerySaverPlus.saveFile(file.path);
    } else {
      await downloadFile(
        file: file,
        directory: directory,
        folderName: folderName,
        fileName: fileName,
        onDirectoryChanged: onDirectoryChanged,
      );
    }
  }

  static Future<T> _throwOnNull<T>(FutureOr<T?> future, String message) async {
    T? result = await future;
    if (result == null) {
      throw FileDownloadException(message);
    }
    return result;
  }
}

class FileDownloadException implements Exception {
  FileDownloadException(this.message) : inner = null;

  FileDownloadException.from(Object this.inner) : message = null;

  final String? message;
  final Object? inner;

  @override
  String toString() {
    if (message != null) {
      return '$runtimeType: $message';
    }
    if (inner != null) {
      if (inner is FileDownloadException) {
        return inner.toString();
      }
      return '$runtimeType: $inner';
    }
    return '$runtimeType: unknown cause!';
  }
}
