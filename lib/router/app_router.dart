import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/screens/home_screen.dart';
import '../features/race/screens/race_detail_screen.dart';
import '../features/race/screens/race_result_screen.dart';
import '../features/horse/screens/horse_detail_screen.dart';
import '../features/prediction/screens/prediction_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/race/:meet/:date/:raceNo',
      builder: (context, state) => RaceDetailScreen(
        meet: state.pathParameters['meet']!,
        date: state.pathParameters['date']!,
        raceNo: int.parse(state.pathParameters['raceNo']!),
      ),
    ),
    GoRoute(
      path: '/result/:meet/:date/:raceNo',
      builder: (context, state) => RaceResultScreen(
        meet: state.pathParameters['meet']!,
        date: state.pathParameters['date']!,
        raceNo: int.parse(state.pathParameters['raceNo']!),
      ),
    ),
    GoRoute(
      path: '/horse/:horseName',
      builder: (context, state) => HorseDetailScreen(
        horseName: state.pathParameters['horseName']!,
        meet: state.uri.queryParameters['meet'] ?? '1',
      ),
    ),
    GoRoute(
      path: '/prediction/:meet/:date/:raceNo',
      builder: (context, state) => PredictionScreen(
        meet: state.pathParameters['meet']!,
        date: state.pathParameters['date']!,
        raceNo: int.parse(state.pathParameters['raceNo']!),
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('페이지를 찾을 수 없습니다: ${state.error}'),
    ),
  ),
);
