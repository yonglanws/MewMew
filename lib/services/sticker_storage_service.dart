import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class StickerStorageService {
  static const _uuid = Uuid();

  static Future<String> importFile(
    XFile source, {
    required String groupId,
    required String folderId,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final stickers = Directory('${directory.path}/stickers/$groupId/$folderId');
    await stickers.create(recursive: true);
    final index = source.path.lastIndexOf('.');
    final extension = index < 0 ? '.png' : source.path.substring(index);
    final target = File('${stickers.path}/${_uuid.v4()}$extension');
    await File(source.path).copy(target.path);
    return target.path;
  }

  static Future<void> deleteFile(String path) async {
    if (path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
