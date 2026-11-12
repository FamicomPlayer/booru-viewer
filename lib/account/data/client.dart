import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';
import 'package:e1547/account/account.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/foundation.dart';

class AccountClient {
  AccountClient({
    required this.dio,
    required this.identity,
    required this.traits,
    required this.postsService,
  });

  final Dio dio;
  final Identity identity;
  final ValueNotifier<Traits> traits;
  final PostClient postsService;

  BooruEngine get engine => BooruEngine.fromHost(identity.host);

  Future<void> available() async {
    switch (engine) {
      case BooruEngine.derpibooru:
        await dio.get('/api/v1/json/images/1');
      case BooruEngine.rule34:
        await dio.get('/index.php', queryParameters: {
          'page': 'dapi',
          's': 'post',
          'q': 'index',
          'json': '1',
          'limit': 1,
        });
      case BooruEngine.e621:
        await dio.head('/status.json');
    }
  }

  Future<void> push({required Traits traits, CancelToken? cancelToken}) async {
    Traits previous = this.traits.value;
    this.traits.value = traits;
    if (identity.username == null) return;
    if (engine != BooruEngine.e621) return;

    try {
      if (!listEquals(previous.denylist, traits.denylist)) {
        Map<String, dynamic> body = {
          'user[blacklisted_tags]': traits.denylist.join('\n'),
        };

        await dio.put(
          '/users/${identity.username}.json',
          data: FormData.fromMap(body),
          cancelToken: cancelToken,
        );
      }
    } on DioException {
      this.traits.value = this.traits.value.copyWith(
        denylist: previous.denylist,
      );
      rethrow;
    }
  }

  Future<void> pull({CancelToken? cancelToken}) =>
      get(cancelToken: cancelToken);

  Future<Account?> get({CancelToken? cancelToken}) async {
    if (identity.username == null) return null;

    if (engine != BooruEngine.e621) {
      return Account(
        id: identity.id,
        name: identity.username ?? engine.displayName,
        avatarId: null,
        blacklistedTags: traits.value.denylist.join('\n'),
        perPage: null,
      );
    }

    Account result = await dio
        .get('/users/${identity.username}.json', cancelToken: cancelToken)
        .then((response) => E621Account.fromJson(response.data));

    Post? avatar;

    if (result.avatarId != null) {
      avatar = await postsService.get(
        id: result.avatarId!,
        cancelToken: cancelToken,
      );
    }

    String? avatarUrl = avatar?.file;
    if (avatar != null && result.hasCroppedAvatar && !avatar.isDeleted) {
      String? reference = avatar.file ?? avatar.sample ?? avatar.preview;
      if (reference != null) {
        avatarUrl =
            croppedAvatarUrl(
              reference: reference,
              userId: result.id,
              avatarId: avatar.id,
            ) ??
            avatarUrl;
      }
    }

    traits.value = traits.value.copyWith(
      denylist: result.blacklistedTags?.split('\n').trim() ?? [],
      avatar: avatarUrl,
    );

    return result;
  }
}

extension E621Account on Account {
  static Account fromJson(dynamic json) => pick(json).letOrThrow(
    (pick) => Account(
      id: pick('id').asIntOrThrow(),
      name: pick('name').asStringOrThrow(),
      avatarId: pick('avatar_id').asIntOrNull(),
      hasCroppedAvatar: pick('has_cropped_avatar').asBoolOrFalse(),
      blacklistedTags: pick('blacklisted_tags').asStringOrNull(),
      perPage: pick('per_page').asIntOrNull(),
    ),
  );
}
