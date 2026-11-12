import 'package:e1547/post/post.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';

class RelationshipDisplay extends StatelessWidget {
  const RelationshipDisplay({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final int? parentId = (post.relationships.parentId != null && post.relationships.parentId! > 0)
        ? post.relationships.parentId
        : null;
    final List<int> children = (post.relationships.hasActiveChildren ?? true)
        ? post.relationships.children.where((id) => id > 0).toList()
        : const [];
    if (parentId == null && children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parentId != null) ...[
          const RelationHeader(title: 'Parent'),
          PostRelationTile(id: parentId),
          const Divider(),
        ],
        if (children.isNotEmpty) ...[
          RelationHeader(title: 'Children', count: children.length),
          SizedBox(
            height: postRelationPreviewSize,
            child: ScrollEdgeFade(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: children.length,
                itemBuilder: (context, index) =>
                    PostRelationPreview(id: children[index]),
              ),
            ),
          ),
          const Divider(),
        ],
      ],
    );
  }
}
