import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/screens/home_screen.dart';
import '../features/purchase/screens/subscription_screen.dart';
import '../features/race/screens/race_detail_screen.dart';
import '../features/race/screens/race_entry_screen.dart';
import '../features/race/screens/race_result_screen.dart';
import '../features/horse/screens/horse_detail_screen.dart';
import '../features/prediction/screens/prediction_screen.dart';
import '../models/race_entry.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/race/:meet/:date/:raceNo',
      builder: (context, state) => RaceDetailScreen(
        meet: state.pathParameters['meet']!,
        date: state.pathParameters['date']!,
        raceNo: int.parse(state.pathParameters['raceNo']!),
      ),
    ),
    GoRoute(
      path: '/entry/:meet/:date/:raceNo',
      builder: (context, state) => RaceEntryScreen(
        meet: state.pathParameters['meet']!,
        date: state.pathParameters['date']!,
        raceNo: int.parse(state.pathParameters['raceNo']!),
        initialTabIndex: state.uri.queryParameters['tab'] == 'ai' ? 1 : 0,
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
        entry: state.extra is RaceEntry ? state.extra as RaceEntry : null,
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
    GoRoute(
      path: '/subscription',
      builder: (context, state) => SubscriptionScreen(
        initialProductId:
            state.uri.queryParameters['plan'] == 'premium_yearly'
            ? 'premium_yearly'
            : 'premium_monthly',
        returnToPath: state.uri.queryParameters['returnTo'],
      ),
    ),
  ],
  errorBuilder: (context, state) =>
      Scaffold(body: Center(child: Text('페이지를 찾을 수 없습니다: ${state.error}'))),
);
