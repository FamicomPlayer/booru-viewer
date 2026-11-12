import 'dart:math';

import 'package:e1547/account/account.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/query/query.dart';
import 'package:e1547/settings/settings.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:like_button/like_button.dart';

class LikeDisplay extends StatelessWidget {
  const LikeDisplay({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final client = context.watch<Client>();
    final messenger = ScaffoldMessenger.of(context);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (client.engine == BooruEngine.rule34)
              Row(
                children: [
                  FavoriteButton(post: post),
                  const SizedBox(width: 8),
                  Text(
                    'Score: ${post.score}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              )
            else
              MutationBuilder(
                mutation: client.posts.useVote(id: post.id),
                builder: (context, state, mutate) {
                  final bool enabled = client.canVote && !state.isLoading;
                  return VoteDisplay(
                    vote: post.vote,
                    score: post.score,
                    onUpvote: enabled
                        ? (isLiked) async {
                            mutate((upvote: true, replace: !isLiked)).catchError((
                              error,
                            ) {
                              messenger.showSnackBar(
                                SnackBar(
                                  duration: const Duration(seconds: 1),
                                  content: Text(
                                    'Failed to upvote Post #${post.id}',
                                  ),
                                ),
                              );
                              return error;
                            });
                            return !isLiked;
                          }
                        : null,
                    onDownvote: enabled
                        ? (isLiked) async {
                            mutate((upvote: false, replace: !isLiked)).catchError(
                              (error) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 1),
                                    content: Text(
                                      'Failed to downvote Post #${post.id}',
                                    ),
                                  ),
                                );
                                return error;
                              },
                            );
                            return !isLiked;
                          }
                        : null,
                  );
                },
              ),
            if (client.engine != BooruEngine.rule34)
              Row(
                children: [
                  Text(post.favCount.toString()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.favorite,
                      color: post.isFavorited
                          ? Colors.pinkAccent
                          : IconTheme.of(context).color,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const Divider(),
      ],
    );
  }
}

class FavoriteButton extends StatefulWidget {
  const FavoriteButton({super.key, required this.post});

  final Post post;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final client = context.watch<Client>();
    final settings = context.read<Settings>();
    final messenger = ScaffoldMessenger.of(context);
    final post = widget.post;
    final isFavorited = post.isFavorited;

    return LikeButton(
      key: ValueKey('fav_${post.id}_$isFavorited'),
      isLiked: isFavorited,
      circleColor: const CircleColor(start: Colors.pink, end: Colors.red),
      bubblesColor: const BubblesColor(
        dotPrimaryColor: Colors.pink,
        dotSecondaryColor: Colors.red,
      ),
      likeBuilder: (isLiked) => Icon(
        Icons.favorite,
        color: isLiked ? Colors.pinkAccent : IconTheme.of(context).color,
      ),
      onTap: (isLiked) async {
        if (_loading) return isLiked;

        Identity identity() => context.mounted
            ? context.read<IdentityClient>().identity
            : client.identity;
        final String site = client.engine.displayName;

        // Whether the site takes favorites from this identity: e621 through
        // its API, Rule34 and Derpibooru through their website alone, which
        // asks for a login made in a browser.
        bool online() => identity().needsWebLogin
            ? identity().hasWebLogin
            : client.hasLogin;

        if (!online() && !isLiked) {
          if (identity().needsWebLogin && context.mounted) {
            final proceed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('$site Web Login'),
                content: Text(
                  'Favoriting on $site requires logging into your account once via the web login page so the site grants write access to your favorites.\n\nWould you like to log in now, or save locally?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Save Locally'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Log In'),
                  ),
                ],
              ),
            );
            // Dismissing the dialog is neither of its two answers.
            if (proceed == null) return isLiked;
            if (proceed == true && context.mounted) {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      CookieCapturePage.login(
                        host: client.host,
                        identity: client.identity.id,
                      ),
                ),
              );
            }
          }
          if (!online()) {
            Rule34Post.markFavorited(
              post.id,
              true,
              post: post,
              host: client.host,
            );
            client.posts.postCache.set(
              post.copyWith(isFavorited: true, favCount: post.favCount + 1),
            );
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  identity().needsWebLogin
                      ? 'Saved to Local Favorites! (Log in to sync with $site)'
                      : 'Saved to Local Favorites!',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            return true;
          }
        }

        // A favorite that only this device knows of is taken back on it, the
        // site would not hear of it from this identity.
        if (!online() &&
            isLiked &&
            LocalFavorites.isFavorited(client.host, post.id)) {
          Rule34Post.markFavorited(post.id, false, host: client.host);
          client.posts.postCache.set(
            post.copyWith(
              isFavorited: false,
              favCount: max(0, post.favCount - 1),
            ),
          );
          return false;
        }

        final activeClient = context.mounted ? context.read<Client>() : client;
        if (!mounted) return isLiked;
        setState(() => _loading = true);
        try {
          if (isLiked) {
            await activeClient.posts.removeFavorite(post.id);
          } else {
            await activeClient.posts.addFavorite(post.id);
          }

          final newFav = !isLiked;
          // The device keeps a copy of what the site does not tell this
          // identity of again: Rule34 never does, Derpibooru only with a key.
          // Elsewhere it only holds on to what the site has not taken yet.
          final bool keepsCopy = switch (activeClient.engine) {
            BooruEngine.rule34 => true,
            BooruEngine.derpibooru => !activeClient.identity.hasDerpibooruKey,
            BooruEngine.e621 => false,
          };
          if (keepsCopy) {
            Rule34Post.markFavorited(
              post.id,
              newFav,
              post: post,
              host: activeClient.host,
            );
          } else {
            await LocalFavorites.remove(activeClient.host, post.id);
          }
          final updatedPost = post.copyWith(
            isFavorited: newFav,
            favCount: newFav ? post.favCount + 1 : max(0, post.favCount - 1),
          );
          activeClient.posts.postCache.set(updatedPost);

          if (newFav && settings.upvoteFavs.value) {
            try {
              await activeClient.posts.useVote(id: post.id).mutate((
                upvote: true,
                replace: true,
              ));
            } on Object catch (_) {}
          }
          return newFav;
        } on Object catch (e) {
          // Where favorites can be handed in later, one that the site did
          // not take is kept for that.
          if (!isLiked && activeClient.identity.needsWebLogin) {
            Rule34Post.markFavorited(
              post.id,
              true,
              post: post,
              host: activeClient.host,
            );
            activeClient.posts.postCache.set(post.copyWith(isFavorited: true));
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Could not favorite on $site: $e\nSaved to Local Favorites instead.',
                ),
              ),
            );
            return true;
          }
          messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text(
                'Failed to ${isLiked ? 'unfavorite' : 'favorite'} Post #${post.id}: $e',
              ),
            ),
          );
          return isLiked;
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      },
    );
  }
}
