import 'dart:math';

import 'package:e1547/client/client.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/settings/settings.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';

class PostDetail extends StatefulWidget {
  const PostDetail({super.key, required this.post, this.onTapImage});

  final Post post;
  final VoidCallback? onTapImage;

  @override
  State<PostDetail> createState() => _PostDetailState();
}

class _PostDetailState extends State<PostDetail> {
  late Post _currentPost;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    final client = context.read<Client>();
    if (client.engine == BooruEngine.rule34) {
      final cached = client.posts.postCache.get(widget.post.id);
      if (cached != null) {
        _currentPost = cached;
      } else {
        final allTags = widget.post.tags.values.expand((e) => e).toList();
        final freshMap = Rule34Post.categorizeAllTags(allTags, source: widget.post.sources.join(' '));
        if (freshMap['artist']!.isNotEmpty && (_currentPost.tags['artist']?.isEmpty ?? true)) {
          _currentPost = widget.post.copyWith(tags: freshMap);
        }
      }
    }
    _checkResolve();
  }

  @override
  void didUpdateWidget(covariant PostDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _currentPost = widget.post;
      _checkResolve();
    }
  }

  void _checkResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _resolving) return;
      final client = context.read<Client>();
      if (client.engine == BooruEngine.rule34) {
        final cached = client.posts.postCache.get(widget.post.id);
        final postToUse = cached ?? _currentPost;
        final hasUnresolved = (postToUse.tags['artist']?.isEmpty ?? true) &&
            (postToUse.tags['general']?.isNotEmpty ?? false);
        if (hasUnresolved) {
          _resolving = true;
          try {
            final resolved = await Rule34Post.resolveTagCategories(postToUse, client.dio);
            if (mounted) {
              setState(() {
                _currentPost = resolved;
              });
              client.posts.postCache.set(resolved);
            }
          } catch (_) {} finally {
            _resolving = false;
          }
        } else if (cached != null && cached != _currentPost) {
          setState(() {
            _currentPost = cached;
          });
        }
      }
    });
  }

  Widget image(BuildContext context, Size size) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: (size.height / 2),
        maxHeight: size.width > size.height
            ? max(400, size.height * 0.8)
            : double.infinity,
      ),
      child: AnimatedSize(
        duration: defaultAnimationDuration,
        child: PostDetailImageDisplay(
          post: _currentPost,
          onTap: () {
            PostVideoRoute.of(context).keepPlaying();
            if (widget.onTapImage != null) {
              widget.onTapImage!();
            } else {
              Navigator.of(context).push(
                DismissRoute<void>(
                  builder: (context) => PostFullscreen(post: _currentPost),
                ),
              );
            }
          },
        ),
      ),
    ),
  );

  Widget upperBody(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArtistDisplay(post: _currentPost),
        DeletionDisplay(post: _currentPost),
        LikeDisplay(post: _currentPost),
        DescriptionDisplay(post: _currentPost),
      ],
    ),
  );

  Widget middleBody(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(children: [CommentDisplay(post: _currentPost)]),
  );

  Widget lowerBody(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      children: [
        RelationshipDisplay(post: _currentPost),
        PoolDisplay(post: _currentPost),
        DenylistTagDisplay(post: _currentPost),
        TagDisplay(post: _currentPost),
        FileDisplay(post: _currentPost),
        SourceDisplay(post: _currentPost),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final post = _currentPost;
    return PostVideoRoute(
      post: post,
      child: PostHistoryConnector(
        post: post,
        child: ScrollToDismiss(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: PostDetailAppBar(post: post),
            floatingActionButtonLocation: Handedness.of(
              context,
            ).floatingActionButtonLocation,
            floatingActionButton:
                (context.read<Client>().hasLogin &&
                    context.read<Client>().engine != BooruEngine.rule34)
                ? DismissFade(child: PostDetailFab(post: post))
                : null,
            body: MediaQuery.removeViewInsets(
              context: context,
              removeTop: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DismissFade(
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final size = MediaQuery.sizeOf(context);
                      if (size.width < 1000) {
                        return ListView(
                          primary: true,
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top,
                            bottom: kBottomNavigationBarHeight + 24,
                          ),
                          children: [
                            image(context, size),
                            DismissFade(child: upperBody(context)),
                            DismissFade(child: middleBody(context)),
                            DismissFade(child: lowerBody(context)),
                          ],
                        );
                      } else {
                        double sideBarWidth;
                        if (size.width > 1400) {
                          sideBarWidth = 404;
                        } else {
                          sideBarWidth = 304;
                        }
                        return CustomScrollView(
                          primary: true,
                          slivers: [
                            SliverCrossAxisGroup(
                              slivers: [
                                SliverMainAxisGroup(
                                  slivers: [
                                    SliverToBoxAdapter(
                                      child: Column(
                                        children: [
                                          image(context, size),
                                          DismissFade(
                                            child: upperBody(context),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DismissSliverFade(
                                      sliver: SliverPostCommentSection(
                                        postId: post.id,
                                      ),
                                    ),
                                  ],
                                ),
                                SliverConstrainedCrossAxis(
                                  maxExtent: sideBarWidth,
                                  sliver: SliverToBoxAdapter(
                                    child: DismissFade(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(height: 56),
                                          lowerBody(context),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
