import 'package:flutter/material.dart';

enum GameType {
  pong,
  tanks,
  shooter,
}

class GameInfo {
  final GameType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color baseColor;

  const GameInfo({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.baseColor,
  });
}

const List<GameInfo> availableGames = [
  GameInfo(
    type: GameType.pong,
    title: 'PONG',
    subtitle: 'CLASSIC DEFLECTION',
    icon: Icons.sports_tennis,
    baseColor: Colors.cyanAccent,
  ),
  GameInfo(
    type: GameType.tanks,
    title: 'TANKS',
    subtitle: 'COMING SOON',
    icon: Icons.directions_car,
    baseColor: Colors.orangeAccent,
  ),
  GameInfo(
    type: GameType.shooter,
    title: 'SPACE SHOOTER',
    subtitle: 'COMING SOON',
    icon: Icons.rocket_launch,
    baseColor: Colors.redAccent,
  ),
];
