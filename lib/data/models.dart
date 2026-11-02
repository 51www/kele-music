// 数据模型。手写 fromJson（不依赖代码生成），保证 clone 后无需 build_runner 即可编译。

int _localIdSeq = 0;

/// 本地资源（「本地」页签的歌单 / 导入曲目）专用 id 生成：负值时间戳序号，
/// 与云端（网易云）正数 id 空间天然隔离，永不冲突。
int nextLocalMediaId() =>
    -(DateTime.now().millisecondsSinceEpoch * 10 + (_localIdSeq++ % 10));

class Artist {
  final int id;
  final String name;
  const Artist({required this.id, required this.name});
  factory Artist.fromJson(Map<String, dynamic> j) =>
      Artist(id: j['id'] ?? 0, name: (j['name'] ?? '').toString());
}

class Album {
  final int id;
  final String name;
  final String picUrl;
  const Album({required this.id, required this.name, required this.picUrl});
  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: j['id'] ?? 0,
        name: (j['name'] ?? '').toString(),
        picUrl: (j['picUrl'] ?? j['blurPicUrl'] ?? '').toString(),
      );
}

class Song {
  final int id;
  final String name;
  final List<Artist> artists;
  final Album album;
  final int duration; // 毫秒
  final int fee;
  final String? url;

  const Song({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.duration,
    required this.fee,
    this.url,
  });

  /// 兼容两种字段命名：
  /// 搜索结果用 album/artists/duration；歌单详情用 al/ar/dt。
  factory Song.fromJson(Map<String, dynamic> j) {
    final albumJson =
        (j['album'] ?? j['al']) as Map<String, dynamic>? ?? <String, dynamic>{};
    final artistsJson = (j['artists'] ?? j['ar']) as List? ?? <dynamic>[];
    return Song(
      id: j['id'] ?? 0,
      name: (j['name'] ?? '').toString(),
      artists: artistsJson
          .map((a) => Artist.fromJson(a as Map<String, dynamic>))
          .toList(),
      album: Album.fromJson(albumJson),
      duration: j['duration'] ?? j['dt'] ?? 0,
      fee: j['fee'] ?? 0,
      url: j['url'] as String?,
    );
  }

  String get coverUrl => album.picUrl;
  String get artistName =>
      artists.map((a) => a.name).where((n) => n.isNotEmpty).join(' / ');
  bool get isVip => fee == 1;

  /// 从本地音频文件路径构造 Song（「本地」页签导入用）。
  /// 文件名按「歌手 - 标题」惯例解析（无分隔则歌手显示「本地音乐」）。
  /// duration 未知置 0：播放器装载成功后由 handler 用实测时长回填媒体通知。
  factory Song.fromLocalFilePath(String filePath) {
    final fileName = filePath.split(RegExp(r'[\\/]')).last;
    var title = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    var artist = '本地音乐';
    final dash = title.indexOf(' - ');
    if (dash > 0 && dash < title.length - 3) {
      artist = title.substring(0, dash).trim();
      title = title.substring(dash + 3).trim();
    }
    return Song(
      id: nextLocalMediaId(),
      name: title.isEmpty ? fileName : title,
      artists: [Artist(id: -1, name: artist)],
      album: const Album(id: -1, name: '本地音乐', picUrl: ''),
      duration: 0,
      fee: 0,
      // 统一存 file:// URI：urlResolver 命中后可直接交给 _loadSource。
      url: Uri.file(filePath).toString(),
    );
  }

  /// 序列化（播放历史等本地持久化用）；fromJson 可直接还原。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'duration': duration,
        'fee': fee,
        'url': url,
        'album': {
          'id': album.id,
          'name': album.name,
          'picUrl': album.picUrl,
        },
        'artists': artists.map((a) => {'id': a.id, 'name': a.name}).toList(),
      };
}

class Playlist {
  final int id;
  final String name;
  final String coverImgUrl;
  final int trackCount;
  final int playCount;
  const Playlist({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.trackCount,
    required this.playCount,
  });
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] ?? 0,
        name: (j['name'] ?? '').toString(),
        coverImgUrl: (j['coverImgUrl'] ?? j['picUrl'] ?? '').toString(),
        trackCount: j['trackCount'] ?? 0,
        playCount: j['playCount'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'coverImgUrl': coverImgUrl,
        'trackCount': trackCount,
        'playCount': playCount,
      };
}

/// 歌单详情：元信息 + 完整曲目列表（/playlist/detail 一次返回）。
class PlaylistDetail {
  final Playlist playlist;
  final List<Song> tracks;
  const PlaylistDetail({required this.playlist, required this.tracks});
}

/// 本地歌单（「本地」页签）：设备本地音频文件的歌单，仅存本机 LocalStore，
/// 与登录态无关。曲目内嵌 Song 序列化（url 为 file:// 本地路径）。
class LocalPlaylist {
  final int id;
  final String name;
  final List<Song> songs;
  const LocalPlaylist(
      {required this.id, required this.name, required this.songs});
  factory LocalPlaylist.fromJson(Map<String, dynamic> j) => LocalPlaylist(
        id: j['id'] ?? 0,
        name: (j['name'] ?? '').toString(),
        songs: (j['songs'] as List? ?? [])
            .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songs': songs.map((s) => s.toJson()).toList(),
      };
}

class BannerItem {
  final String imageUrl;
  final String? title;
  final String? typeTitle;
  final String? url;
  const BannerItem({
    required this.imageUrl,
    this.title,
    this.typeTitle,
    this.url,
  });
  factory BannerItem.fromJson(Map<String, dynamic> j) => BannerItem(
        imageUrl: (j['imageUrl'] ?? j['pic'] ?? '').toString(),
        title: j['title'] as String?,
        typeTitle: j['typeTitle'] as String?,
        url: j['url'] as String?,
      );
}

class Ranking {
  final int id;
  final String name;
  final String coverImgUrl;
  final String updateFrequency;
  const Ranking({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.updateFrequency,
  });
  factory Ranking.fromJson(Map<String, dynamic> j) => Ranking(
        id: j['id'] ?? 0,
        name: (j['name'] ?? '').toString(),
        coverImgUrl: (j['coverImgUrl'] ?? j['picUrl'] ?? '').toString(),
        updateFrequency: (j['updateFrequency'] ?? '').toString(),
      );

  /// 序列化（发现页本地缓存用）；fromJson 可直接还原。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'coverImgUrl': coverImgUrl,
        'updateFrequency': updateFrequency,
      };
}

class Lyric {
  final String? text;
  final String? trans;
  const Lyric({this.text, this.trans});
  factory Lyric.fromJson(Map<String, dynamic> j) => Lyric(
        text: (j['lrc']?['lyric'] as String?) ?? (j['lyric'] as String?),
        trans: (j['tlyric']?['lyric'] as String?),
      );
}

/// 登录用户资料（/user/account）。未登录时为空值实例。
class UserProfile {
  final int userId;
  final String nickname;
  final String avatarUrl;
  const UserProfile({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
  });

  bool get isEmpty => userId == 0 && nickname.isEmpty;
}
