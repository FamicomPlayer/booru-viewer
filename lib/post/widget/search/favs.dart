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

/// Hands the favorites kept on this device to the account on the site of
/// [client]. Favorites the site already has are left as they are, so this
/// may be run again at any time.
Future<void> syncLocalFavorites(
  Client client,
  ScaffoldMessengerState messenger,
) async {
  final String site = client.engine.displayName;
  try {
    if (!client.identity.hasWebLogin) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Log in through Web Login to sync with $site.'),
        ),
      );
      return;
    }
    final localPosts = await LocalFavorites.getLocalFavorites(client.host);
    if (localPosts.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('There are no local favorites to sync.')),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Syncing ${localPosts.length} local favorites to $site...',
        ),
      ),
    );

    int synced = 0;
    int failed = 0;
    for (final post in localPosts) {
      try {
        await client.posts.addFavorite(post.id);
        synced++;
      } on WebLoginException catch (e) {
        // A login the site does not take fails every favorite alike.
        messenger.showSnackBar(
          SnackBar(content: Text('Synced $synced favorites, then stopped: $e')),
        );
        return;
      } on Object {
        failed++;
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Successfully synced $synced favorites to your $site account!'
              : 'Synced $synced favorites to $site ($failed failed).',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Sync error: $e')));
  }
}

class _FavPageState extends State<FavPage> {
  bool _showLocalFavorites = false;
  bool _syncing = false;

  Future<void> _syncLocalFavorites(BuildContext context) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await syncLocalFavorites(
        context.read<Client>(),
        ScaffoldMessenger.of(context),
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
    // Derpibooru only lists favorites for its API key, a web login alone
    // does not get to read them.
    final String? derpibooruKey =
        client.identity.headers?['key'] ?? client.identity.headers?['X-API-Key'];
    final bool hasServerLogin =
        client.hasLogin &&
        (!isRule34 || userId != null) &&
        (client.engine != BooruEngine.derpibooru ||
            (derpibooruKey?.isNotEmpty ?? false));
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
                        if (client.identity.hasWebLogin)
                          IconButton(
                            icon: _syncing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync),
                            tooltip: 'Sync Favorites with ${client.engine.displayName}',
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
                      if (client.identity.hasWebLogin) ...[
                        ListTile(
                          leading: const Icon(Icons.sync),
                          title: const Text('Sync Favorites'),
                          subtitle: Text('Upload local favorites to ${client.engine.displayName}'),
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
                                    if (!context.mounted) return;
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
    required this.hasServerLogin,
    this.onSwitchToOnline,
  });

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

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await syncLocalFavorites(
        context.read<Client>(),
        ScaffoldMessenger.of(context),
      );
      // The device may hold fewer of them now, and the page may be gone.
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<Client>();
    final String site = client.engine.displayName;
    final bool needsWebLogin = client.identity.needsWebLogin;
    final bool hasWebLogin = client.identity.hasWebLogin;
    return AdaptiveScaffold(
      appBar: DefaultAppBar(
        title: const Text('Local Favorites'),
        actions: [
          if (widget.hasServerLogin || hasWebLogin) ...[
            if (hasWebLogin)
              IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              tooltip: 'Sync Favorites with $site',
              onPressed: _syncing ? null : _sync,
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
          if (needsWebLogin && !hasWebLogin)
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
                      'Log in to sync favorites with your $site account',
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
                          builder: (context) =>
                              CookieCapturePage.login(
                                host: client.host,
                                identity: client.identity.id,
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
          if (needsWebLogin && hasWebLogin)
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
                      client.engine == BooruEngine.derpibooru &&
                              !client.identity.hasDerpibooruKey
                          ? '$site account connected. Favorites made here are sent to the site. Add your API key to this account to browse the ones made elsewhere.'
                          : '$site account connected. Tap Sync to upload your local favorites to the server.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _syncing ? null : _sync,
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
                          needsWebLogin
                              ? 'No local favorites yet\nTap the heart icon on any post to save it locally, or switch to Online to browse your $site favorites.'
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
