import 'package:e1547/client/client.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/tag/tag.dart';
import 'package:flutter/material.dart';

class TagDisplay extends StatefulWidget {
  const TagDisplay({super.key, required this.post});

  final Post post;

  @override
  State<TagDisplay> createState() => _TagDisplayState();
}

class _TagDisplayState extends State<TagDisplay> {
  Post? _resolvedPost;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _checkResolve();
  }

  @override
  void didUpdateWidget(covariant TagDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _resolvedPost = null;
      _checkResolve();
    } else if (oldWidget.post != widget.post) {
      setState(() {
        _resolvedPost = widget.post;
      });
    }
  }

  void _checkResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _resolving) return;
      final client = context.read<Client>();
      if (client.engine == BooruEngine.rule34) {
        final currentPost = _resolvedPost ?? widget.post;
        final hasUnresolved = (currentPost.tags['artist']?.isEmpty ?? true) &&
            (currentPost.tags['general']?.isNotEmpty ?? false);
        if (hasUnresolved) {
          _resolving = true;
          try {
            final resolved = await Rule34Post.resolveTagCategories(currentPost, client.dio);
            if (mounted) {
              setState(() {
                _resolvedPost = resolved;
              });
              client.posts.postCache.set(resolved);
            }
          } finally {
            _resolving = false;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = _resolvedPost ?? widget.post;

    Widget tagCategory(String category) {
      return Wrap(
        children: [
          ...post.tags[category]!.map(
            (tag) => TagCard(tag: tag, category: category),
          ),
        ],
      );
    }

    Widget categoryTile(String category) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              '${category[0].toUpperCase()}${category.substring(1)}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          Row(children: [Expanded(child: tagCategory(category))]),
          const Divider(),
        ],
      );
    }

    const categoryOrder = ['artist', 'copyright', 'character', 'general', 'meta'];
    final sortedKeys = post.tags.keys
        .where((category) => post.tags[category]?.isNotEmpty ?? false)
        .toList()
      ..sort((a, b) {
        int idxA = categoryOrder.indexOf(a);
        int idxB = categoryOrder.indexOf(b);
        if (idxA == -1) idxA = 99;
        if (idxB == -1) idxB = 99;
        return idxA.compareTo(idxB);
      });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: sortedKeys.map((category) => categoryTile(category)).toList(),
    );
  }
}
