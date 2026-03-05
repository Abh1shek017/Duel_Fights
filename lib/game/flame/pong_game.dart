import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart' hide Image;

import '../pong_engine.dart';
import 'components/ball.dart';
import 'components/paddle.dart';

class PongGame extends FlameGame with PanDetector {
  final PongEngine engine;
  final bool isHost;

  PongGame({required this.engine, required this.isHost});

  @override
  Future<void> onLoad() async {
    // 800x500 Fixed aspect ratio
    camera = CameraComponent.withFixedResolution(
      width: engine.fieldWidth,
      height: engine.fieldHeight,
    );
    camera.viewfinder.anchor = Anchor.topLeft;
    world = World();

    // Deep frosted game board background
    world.add(
      RectangleComponent(
        size: Vector2(engine.fieldWidth, engine.fieldHeight),
        paint: Paint()..color = const Color(0xFF000000).withValues(alpha: 0.2),
      ),
    );

    // Sleek border
    world.add(
      RectangleComponent(
        size: Vector2(engine.fieldWidth, engine.fieldHeight),
        paint: Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      ),
    );

    // Center divider
    world.add(_CenterDivider(engine: engine));

    // Ball
    world.add(PongBall(engine));

    // Paddles
    world.add(
      PongPaddle(
        engine: engine,
        isHostPaddle: true,
        accentColor: const Color(0xFF38BDF8),
      ),
    );
    world.add(
      PongPaddle(
        engine: engine,
        isHostPaddle: false,
        accentColor: const Color(0xFFF472B6),
      ),
    );

    add(world);
  }

  // --- Input Tracking Variables ---
  double? _touchStartY;
  double? _paddleStartY;

  @override
  void onPanStart(DragStartInfo info) {
    // Convert global screen touch to local Game viewport coordinates
    final v2pos = Vector2(
      info.eventPosition.global.x,
      info.eventPosition.global.y,
    );
    final localPosition = camera.globalToLocal(v2pos);
    _touchStartY = localPosition.y;

    if (isHost) {
      _paddleStartY = engine.paddle1Y;
    } else {
      _paddleStartY = engine.paddle2Y;
    }
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (_touchStartY == null || _paddleStartY == null) return;

    final v2pos = Vector2(
      info.eventPosition.global.x,
      info.eventPosition.global.y,
    );
    final localPosition = camera.globalToLocal(v2pos);
    final deltaY = localPosition.y - _touchStartY!;
    final newY = (_paddleStartY! + deltaY).clamp(
      PongEngine.paddleHeight / 2,
      engine.fieldHeight - PongEngine.paddleHeight / 2,
    );

    if (isHost) {
      engine.paddle1Y = newY;
    } else {
      engine.paddle2Y = newY;
    }
  }

  @override
  void onPanEnd(DragEndInfo info) {
    _touchStartY = null;
    _paddleStartY = null;
  }

  @override
  void onPanCancel() {
    _touchStartY = null;
    _paddleStartY = null;
  }

  @override
  void pauseEngine() {
    super.pauseEngine();
  }

  @override
  void resumeEngine() {
    super.resumeEngine();
  }

  void startGame() {
    resumeEngine();
  }

  int _lastScorer = 0;

  @override
  void update(double dt) {
    if (isHost && !paused) {
      final scorer = engine.update(dt);
      if (scorer != 0) {
        _lastScorer = scorer;
      }
    }
    super.update(dt);
  }

  int getAndResetScorer() {
    final s = _lastScorer;
    _lastScorer = 0;
    return s;
  }
}

class _CenterDivider extends PositionComponent {
  final PongEngine engine;

  _CenterDivider({required this.engine});

  @override
  void render(Canvas canvas) {
    final centerX = engine.fieldWidth / 2;
    final dividerPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.08)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (double y = 16; y < engine.fieldHeight - 16; y += 32) {
      canvas.drawLine(
        Offset(centerX, y),
        Offset(centerX, y + 16),
        dividerPaint,
      );
    }
  }
}
