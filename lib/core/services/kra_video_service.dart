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
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.todayRaceBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
    ),
  );
  final Dio _youtubeDio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.youtubeApiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  static String? _cachedYoutubeChannelId;

  Future<RaceVideoLinks> getRaceVideoLinks({
    required String meet,
    required String date,
    required int raceNo,
  }) async {
    final query = <String, String>{
      'rcDate': date,
      'rcNo': raceNo.toString(),
      // todayrace 페이지는 서버 사이드 렌더링이라 파라미터 인식 방식이 변경될 수 있어
      // 숫자 코드와 이름 코드를 함께 전달합니다.
      'meet': meet,
      'rcMeet': _mapMeetToSiteCode(meet),
    };

    final fallbackRaceVideo = _buildYoutubeSearchUrl(
      keyword: '${_meetName(meet)} ${raceNo}R ${_formatDateHyphen(date)} 경주영상',
    );
    final paradeVideo = _buildYoutubeSearchUrl(
      keyword:
          '${_meetName(meet)} ${raceNo}R ${_formatDateHyphen(date)} 경주로 입장',
    );

    try {
      final youtubeVideoUrl = await _fetchYoutubeRaceVideoUrl(
        meet: meet,
        date: date,
        raceNo: raceNo,
      );
      final response = await _dio.get(
        ApiConstants.todayRaceScorePath,
        queryParameters: query,
      );
      final html = response.data?.toString() ?? '';
      final hasRaceTitle = html.contains('제 $raceNo경주');
      final hasVideoText = html.contains('경주영상');

      return RaceVideoLinks(
        // 사용자 요청: 경주영상은 유튜브 연결
        liveUrl: youtubeVideoUrl ?? fallbackRaceVideo,
        paradeUrl: paradeVideo,
        hasVideoSection: hasRaceTitle && hasVideoText,
        isRaceVideoFromApi: youtubeVideoUrl != null,
      );
    } catch (_) {
      // 요청 실패 시에도 사용자가 바로 볼 수 있도록 영상 페이지 링크는 반환합니다.
      final youtubeVideoUrl = await _fetchYoutubeRaceVideoUrl(
        meet: meet,
        date: date,
        raceNo: raceNo,
      );
      return RaceVideoLinks(
        liveUrl:
            youtubeVideoUrl ??
            (fallbackRaceVideo.isNotEmpty
                ? fallbackRaceVideo
                : _buildYoutubeSearchUrl(
                    keyword:
                        '${_meetName(meet)} ${raceNo}R ${_formatDateHyphen(date)} 경주영상',
                  )),
        paradeUrl: paradeVideo,
        hasVideoSection: false,
        isRaceVideoFromApi: youtubeVideoUrl != null,
      );
    }
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

  String _mapMeetToSiteCode(String meet) {
    switch (meet) {
      case '1':
        return 'S';
      case '2':
        return 'J';
      case '3':
        return 'B';
      default:
        return meet;
    }
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
