import 'package:dio/dio.dart';

import '../constants/api_constants.dart';
import 'runtime_secrets_service.dart';

class RaceVideoLinks {
  const RaceVideoLinks({
    required this.liveUrl,
    required this.paradeUrl,
    required this.hasVideoSection,
    required this.isRaceVideoFromApi,
  });

  final String liveUrl;
  final String paradeUrl;
  final bool hasVideoSection;
  final bool isRaceVideoFromApi;
}

class KraVideoService {
  final Dio _youtubeDio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.youtubeApiBaseUrl,
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 4),
    ),
  );
  static final Map<String, RaceVideoLinks> _cache = {};
  static String? _cachedYoutubeChannelId;

  Future<RaceVideoLinks> getRaceVideoLinks({
    required String meet,
    required String date,
    required int raceNo,
  }) async {
    final cacheKey = '$meet-$date-$raceNo';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final fallbackRaceVideo = _buildYoutubeSearchUrl(
      keyword: '${_meetName(meet)} ${raceNo}R ${_formatDateHyphen(date)} 경주영상',
    );
    final paradeVideo = _buildYoutubeSearchUrl(
      keyword:
          '${_meetName(meet)} ${raceNo}R ${_formatDateHyphen(date)} 경주로 입장',
    );

    final youtubeVideoUrl = await _fetchYoutubeRaceVideoUrl(
      meet: meet,
      date: date,
      raceNo: raceNo,
    );
    final links = RaceVideoLinks(
      liveUrl: youtubeVideoUrl ?? fallbackRaceVideo,
      paradeUrl: paradeVideo,
      hasVideoSection: false,
      isRaceVideoFromApi: youtubeVideoUrl != null,
    );
    _cache[cacheKey] = links;
    return links;
  }

  Future<String?> _fetchYoutubeRaceVideoUrl({
    required String meet,
    required String date,
    required int raceNo,
  }) async {
    final apiKey = await RuntimeSecretsService.getYoutubeApiKey();
    if (apiKey.isEmpty) return null;

    final channelId = await _resolveYoutubeChannelId(apiKey);
    if (channelId == null) return null;

    final formatted = _formatDateHyphen(date);
    final meetName = _meetName(meet);
    final query = '$meetName ${raceNo}R $formatted 경주영상';

    try {
      final response = await _youtubeDio.get(
        '/youtube/v3/search',
        queryParameters: {
          'part': 'snippet',
          'channelId': channelId,
          'type': 'video',
          'order': 'date',
          'maxResults': 10,
          'q': query,
          'key': apiKey,
        },
      );

      final items = (response.data is Map<String, dynamic>)
          ? (response.data['items'] as List<dynamic>?)
          : null;
      if (items == null || items.isEmpty) return null;

      String? bestVideoId;
      var bestScore = -1;
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['id'] as Map<String, dynamic>?;
        final snippet = item['snippet'] as Map<String, dynamic>?;
        final videoId = id?['videoId']?.toString();
        final title = snippet?['title']?.toString() ?? '';
        if (videoId == null || videoId.isEmpty) continue;

        final score = _scoreYoutubeTitle(
          title: title,
          meetName: meetName,
          raceNo: raceNo,
          formattedDate: formatted,
        );
        if (score > bestScore) {
          bestScore = score;
          bestVideoId = videoId;
        }
      }

      if (bestVideoId == null) return null;
      return 'https://www.youtube.com/watch?v=$bestVideoId';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveYoutubeChannelId(String apiKey) async {
    if (_cachedYoutubeChannelId == '') return null;
    if (_cachedYoutubeChannelId != null) return _cachedYoutubeChannelId;

    try {
      final response = await _youtubeDio.get(
        '/youtube/v3/channels',
        queryParameters: {
          'part': 'id',
          'forHandle': ApiConstants.youtubeChannelHandle,
          'maxResults': 1,
          'key': apiKey,
        },
      );
      final items = (response.data is Map<String, dynamic>)
          ? (response.data['items'] as List<dynamic>?)
          : null;
      if (items == null || items.isEmpty) return null;
      final first = items.first;
      if (first is! Map<String, dynamic>) return null;
      final channelId = first['id']?.toString();
      if (channelId == null || channelId.isEmpty) return null;
      _cachedYoutubeChannelId = channelId;
      return channelId;
    } catch (_) {
      _cachedYoutubeChannelId = '';
      return null;
    }
  }

  int _scoreYoutubeTitle({
    required String title,
    required String meetName,
    required int raceNo,
    required String formattedDate,
  }) {
    var score = 0;
    if (title.contains(meetName)) score += 3;
    if (title.contains('${raceNo}R') ||
        title.contains('제$raceNo경주') ||
        title.contains('제 $raceNo경주')) {
      score += 4;
    }
    if (title.contains(formattedDate)) score += 3;
    if (title.contains('경주')) score += 1;
    return score;
  }

  String _meetName(String meet) {
    switch (meet) {
      case '1':
        return '서울';
      case '2':
        return '제주';
      case '3':
        return '부산경남';
      default:
        return meet;
    }
  }

  String _formatDateHyphen(String date) {
    if (date.length != 8) return date;
    return '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)}';
  }

  String _buildYoutubeSearchUrl({required String keyword}) {
    return Uri.https('www.youtube.com', '/results', {
      'search_query': '$keyword 한국마사회 e오늘의경주',
    }).toString();
  }
}
