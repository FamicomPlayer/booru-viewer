import 'dart:io';

import 'package:e1547/account/widget/cookie.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/query/query.dart';
import 'package:e1547/settings/settings.dart';
import 'package:e1547/shared/data/rule34_api_key.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/tag/tag.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/material.dart';

class FavPage extends StatefulWidget {
  const FavPage({super.key});

  @override
  State<FavPage> createState() => _FavPageState();
}

class _FavPageState extends State<FavPage> {
  bool _showLocalFavorites = false;
  bool _syncing = false;

  Future<void> _syncLocalFavorites(BuildContext context) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final client = context.read<Client>();
      final localPosts = await LocalFavorites.getLocalFavorites(client.host);
      if (localPosts.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('There are no local favorites to sync.')),
        );
        return;
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Syncing ${localPosts.length} local favorites to Rule34.xxx...')),
      );

      int synced = 0;
      int failed = 0;
      for (final post in localPosts) {
        try {
          await client.posts.addFavorite(post.id);
          synced++;
        } on Object catch (_) {
          failed++;
        }
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Successfully synced $synced favorites to your Rule34.xxx account!'
                : 'Synced $synced favorites ($failed failed).',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } on Object catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Sync error: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<Client>();

    String? userId = client.identity.headers?['user_id'];
    if (userId == null || userId.isEmpty) {
      final username = client.identity.username;
      if (username != null) {
        if (int.tryParse(username) != null) {
          userId = username;
        } else if (username.startsWith('User #')) {
          userId = username.substring(6).trim();
        }
      }
    }
    if (userId == null || userId.isEmpty) {
      final cookie = client.identity.headers?[HttpHeaders.cookieHeader];
      if (cookie != null) {
        final match = RegExp(r'user_id=(\d+)').firstMatch(cookie);
        if (match != null) userId = match.group(1);
      }
    }

    final bool isRule34 = client.engine == BooruEngine.rule34;
    final bool hasServerLogin = client.hasLogin && (!isRule34 || userId != null);
    final String? apiKey = client.identity.headers?['api_key'];
    final bool hasApiKey = apiKey != null && apiKey.isNotEmpty;

    final favTags = switch (client.engine) {
      BooruEngine.derpibooru => 'my:faves',
      BooruEngine.rule34 => 'fav:${userId ?? ''}',
      BooruEngine.e621 => 'fav:${client.identity.username ?? ''}',
    };

    if (_showLocalFavorites || !hasServerLogin) {
      return RouterDrawerEntry<FavPage>(
        child: LocalFavoritesView(
          isRule34: isRule34,
          hasServerLogin: hasServerLogin,
          onSwitchToOnline: hasServerLogin
              ? () => setState(() => _showLocalFavorites = false)
              : null,
        ),
      );
    }

    return RouterDrawerEntry<FavPage>(
      child: FilterControllerProvider<PostFilter, Post>(
        create: (_) => FavoritePostFilter(client),
        keys: (_) => [client],
        child: ChangeNotifierProvider(
          create: (_) => PostParamsController(
            initial: PostParams(tags: favTags),
          ),
          child: PostPageHistoryConnector(
            child: PostPageQueryBuilder(
              builder: (context, state, query) => SelectionLayout<Post>(
                items: state.data?.pages.expand((p) => p).toList(),
                child: AdaptiveScaffold(
                  appBar: PostSelectionAppBar(
                    child: PostPageAppBar(
                      actions: [
                        if (client.hasLogin && isRule34)
                          IconButton(
                            icon: _syncing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync),
                            tooltip: 'Sync Favorites with Rule34',
                            onPressed: _syncing ? null : () => _syncLocalFavorites(context),
                          ),
                        IconButton(
                          icon: const Icon(Icons.folder_special_outlined),
                          tooltip: 'View Local Favorites',
                          onPressed: () => setState(() => _showLocalFavorites = true),
                        ),
                      ],
                    ),
                  ),
                  floatingActionButton: const PostsPageFab(),
                  drawer: const RouterDrawer(),
                  endDrawer: ContextDrawer(
                    title: const Text('Posts'),
                    children: [
                      if (client.engine == BooruEngine.e621) ...[
                        const FavoriteOrderSwitch(),
                        const Divider(),
                      ],
                      if (client.hasLogin && isRule34) ...[
                        ListTile(
                          leading: const Icon(Icons.sync),
                          title: const Text('Sync Favorites'),
                          subtitle: const Text('Upload local favorites to Rule34'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _syncLocalFavorites(context);
                          },
                        ),
                        const Divider(),
                      ],
                      ListTile(
                        leading: const Icon(Icons.folder_special),
                        title: const Text('Local Favorites'),
                        subtitle: const Text('View posts saved on this device'),
                        onTap: () {
                          Navigator.of(context).pop();
                          setState(() => _showLocalFavorites = true);
                        },
                      ),
                      const Divider(),
                      const DrawerDenySwitch(),
                      DrawerTagCounter(
                        posts: state.data?.pages.expand((p) => p).toList(),
                        error: state.error,
                      ),
                    ],
                  ),
                  body: Column(
                    children: [
                      if (isRule34 && !hasApiKey)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          color: Theme.of(context).colorScheme.tertiaryContainer,
                          child: Row(
                            children: [
                              Icon(
                                Icons.key,
                                color: Theme.of(context).colorScheme.onTertiaryContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'API Key needed to load online favorites from Rule34.xxx.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: () async {
                                  final idClient = context.read<IdentityClient>();
                                  final key = await fetchRule34ApiKey(identity: client.identity);
                                  if (key != null && key.isNotEmpty && context.mounted) {
                                    final newHeaders = Map<String, String>.from(
                                      client.identity.headers ?? {},
                                    );
                                    newHeaders['api_key'] = key;
                                    await idClient.replace(
                                      client.identity.copyWith(headers: newHeaders),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('API Key retrieved! Loading favorites...'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  } else if (context.mounted) {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => const CookieCapturePage(
                                          title: Text('Rule34 API Credentials'),
                                          initialUrl:
                                              'https://rule34.xxx/index.php?page=account&s=options',
                                          targetHost: 'https://rule34.xxx',
                                          engine: BooruEngine.rule34,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Fetch Key'),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: LimitedWidthLayout(
                          child: ListenableBuilder(
                            listenable: context.watch<Settings>().tileSize,
                            builder: (context, child) => TileLayout(
                              tileSize: context.watch<Settings>().tileSize.value,
                              child: const PostList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LocalFavoritesView extends StatefulWidget {
  const LocalFavoritesView({
    super.key,
    required this.isRule34,
    required this.hasServerLogin,
    this.onSwitchToOnline,
  });

  final bool isRule34;
  final bool hasServerLogin;
  final VoidCallback? onSwitchToOnline;

  @override
  State<LocalFavoritesView> createState() => _LocalFavoritesViewState();
}

class _LocalFavoritesViewState extends State<LocalFavoritesView> {
  List<Post>? _posts;
  bool _loading = true;
  bool _syncing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final client = context.read<Client>();
    final posts = await LocalFavorites.getLocalFavorites(client.host);
    if (mounted) {
      setState(() {
        _posts = posts;
        _loading = false;
      });
    }
  }

  Future<void> _syncWithRule34() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final client = context.read<Client>();
      final localPosts = await LocalFavorites.getLocalFavorites(client.host);
      if (localPosts.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('No local favorites to sync.')),
        );
        return;
      }

      int synced = 0;
      int failed = 0;
      for (final post in localPosts) {
        try {
          await client.posts.addFavorite(post.id);
          synced++;
        } on Object catch (_) {
          failed++;
        }
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Successfully synced $synced favorites to your Rule34 account!'
                : 'Synced $synced favorites to Rule34 ($failed failed).',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } on Object catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Sync error: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: DefaultAppBar(
        title: const Text('Local Favorites'),
        actions: [
          if (widget.hasServerLogin) ...[
            IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              tooltip: 'Sync Favorites with Rule34',
              onPressed: _syncing ? null : _syncWithRule34,
            ),
            if (widget.onSwitchToOnline != null)
              TextButton.icon(
                onPressed: widget.onSwitchToOnline,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Online'),
              ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      drawer: const RouterDrawer(),
      body: Column(
        children: [
          if (widget.isRule34 && !widget.hasServerLogin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Log in to sync favorites with Rule34.xxx server',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () async {
                      final loggedIn = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (context) => const CookieCapturePage(
                            title: Text('Rule34 Web Login'),
                            initialUrl: 'https://rule34.xxx/index.php?page=account&s=login',
                            targetHost: 'https://rule34.xxx',
                            engine: BooruEngine.rule34,
                          ),
                        ),
                      );
                      if (loggedIn == true && mounted) {
                        _load();
                      }
                    },
                    child: const Text('Web Login'),
                  ),
                ],
              ),
            ),
          if (widget.isRule34 && widget.hasServerLogin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_sync_outlined,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Rule34 account connected. Tap Sync to upload your local favorites to the server.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _syncing ? null : _syncWithRule34,
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: const Text('Sync Now'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_posts == null || _posts!.isEmpty)
                    ? IconMessage(
                        icon: const Icon(Icons.favorite_border, size: 64),
                        title: Text(
                          widget.isRule34
                              ? 'No local favorites yet\nTap the heart icon on any post to save it locally, or switch to Online to browse your Rule34 favorites.'
                              : 'No local favorites yet\nTap the heart icon on any post to add it to favorites.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : LimitedWidthLayout(
                        child: ListenableBuilder(
                          listenable: context.watch<Settings>().tileSize,
                          builder: (context, child) => TileLayout(
                            tileSize: context.watch<Settings>().tileSize.value,
                            child: Builder(
                              builder: (innerContext) => GridView.builder(
                                padding: defaultActionListPadding,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: TileLayout.of(innerContext).crossAxisCount,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4,
                                ),
                                itemCount: _posts!.length,
                                itemBuilder: (context, index) {
                                  final post = _posts![index];
                                  return PostTile(
                                    post: post,
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => PostDetail(
                                            post: post,
                                          ),
                                        ),
                                      );
                                      _load();
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class FavoriteOrderSwitch extends StatelessWidget {
  const FavoriteOrderSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PostParamsController>();
    final tags = TagMap(controller.value.tags);
    final order = tags['order'];
    final addedOrder = order == null || order == 'fav';
    return SwitchListTile(
      secondary: const Icon(Icons.sort),
      title: const Text('Favorite order'),
      subtitle: Text(addedOrder ? 'added order' : 'id order'),
      value: addedOrder,
      onChanged: (value) {
        final next = TagMap(controller.value.tags);
        if (value) {
          next.remove('order');
        } else {
          next['order'] = PostOrder.newest.value;
        }
        controller.update((p) => p.copyWith(tags: next.toString()));
      },
    );
  }
}
