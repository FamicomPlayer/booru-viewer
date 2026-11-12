import 'package:e1547/post/post.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/tag/tag.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class FileDisplay extends StatelessWidget {
  const FileDisplay({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text('File', style: TextStyle(fontSize: 16)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: TagGesture(
                  tag: 'rating:${post.rating.name}',
                  child: Text(
                    post.rating.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${post.width} x ${post.height}'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  DateFormatting.dateTime(post.createdAt.toLocal()),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (post.size > 0)
                Text(filesize(post.size, 1))
              else if (post.file != null)
                FutureBuilder<int?>(
                  future: _resolveFileSize(post.file!),
                  builder: (context, snapshot) {
                    final size = snapshot.data;
                    if (size != null && size > 0) {
                      return Text(filesize(size, 1));
                    }
                    return Text(post.ext.toUpperCase());
                  },
                )
              else
                Text(post.ext.toUpperCase()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (post.updatedAt != null)
                Flexible(
                  child: Text(
                    DateFormatting.dateTime(post.updatedAt!.toLocal()),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const SizedBox.shrink(),
              const SizedBox(width: 8),
              TagGesture(tag: 'type:${post.ext}', child: Text(post.ext)),
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }

  static final Map<String, int> _resolvedSizeCache = {};

  static Future<int?> _resolveFileSize(String url) async {
    if (_resolvedSizeCache.containsKey(url)) return _resolvedSizeCache[url];
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(url);
      if (fileInfo != null && fileInfo.file.existsSync()) {
        final length = fileInfo.file.lengthSync();
        _resolvedSizeCache[url] = length;
        return length;
      }
    } on Exception catch (_) {}
    return null;
  }
}
