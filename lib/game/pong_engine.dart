import 'dart:math';

/// Pure-dart Pong physics engine.
/// Host-authoritative: only the host runs [update].
class PongEngine {
  // --- Field dimensions ---
  final double fieldWidth;
  final double fieldHeight;

  // --- Paddle config ---
  static const double paddleWidth = 16;
  static const double paddleHeight = 100;
  static const double paddleMargin = 30;

  // --- Ball config ---
  static const double ballSize = 16;
  double _baseSpeed = 400;

  // --- State ---
  double paddle1Y; // left paddle center-Y
  double paddle2Y; // right paddle center-Y
  double ballX;
  double ballY;
  double ballVX = 0;
  double ballVY = 0;
  int scoreP1 = 0;
  int scoreP2 = 0;
  bool _running = false;

  final Random _rng = Random();

  PongEngine({
    required this.fieldWidth,
    required this.fieldHeight,
  })  : paddle1Y = fieldHeight / 2,
        paddle2Y = fieldHeight / 2,
        ballX = fieldWidth / 2,
        ballY = fieldHeight / 2;

  /// Resets the ball to center, launches in [direction] (-1 = left, 1 = right).
  void resetBall({int direction = 1}) {
    ballX = fieldWidth / 2;
    ballY = fieldHeight / 2;
    _baseSpeed = 400;
    final angle = (_rng.nextDouble() - 0.5) * (pi / 3); // ±30°
    ballVX = cos(angle) * _baseSpeed * direction;
    ballVY = sin(angle) * _baseSpeed;
    _running = true;
  }

  void stopBall() {
    ballVX = 0;
    ballVY = 0;
    _running = false;
  }

  /// Advance physics by [dt] seconds. Returns scoring player (1 or 2) or 0.
  int update(double dt) {
    if (!_running) return 0;

    ballX += ballVX * dt;
    ballY += ballVY * dt;

    // --- Top/bottom wall bounce ---
    if (ballY - ballSize / 2 <= 0) {
      ballY = ballSize / 2;
      ballVY = ballVY.abs();
    } else if (ballY + ballSize / 2 >= fieldHeight) {
      ballY = fieldHeight - ballSize / 2;
      ballVY = -ballVY.abs();
    }

    // --- Left paddle collision ---
    final p1Left = paddleMargin;
    final p1Right = paddleMargin + paddleWidth;
    final p1Top = paddle1Y - paddleHeight / 2;
    final p1Bottom = paddle1Y + paddleHeight / 2;

    if (ballVX < 0 &&
        ballX - ballSize / 2 <= p1Right &&
        ballX + ballSize / 2 >= p1Left &&
        ballY + ballSize / 2 >= p1Top &&
        ballY - ballSize / 2 <= p1Bottom) {
      ballX = p1Right + ballSize / 2;
      _baseSpeed += 15;
      final hitRatio = (ballY - paddle1Y) / (paddleHeight / 2);
      final angle = hitRatio * (pi / 4); // max ±45°
      ballVX = cos(angle) * _baseSpeed;
      ballVY = sin(angle) * _baseSpeed;
    }

    // --- Right paddle collision ---
    final p2Left = fieldWidth - paddleMargin - paddleWidth;
    final p2Right = fieldWidth - paddleMargin;
    final p2Top = paddle2Y - paddleHeight / 2;
    final p2Bottom = paddle2Y + paddleHeight / 2;

    if (ballVX > 0 &&
        ballX + ballSize / 2 >= p2Left &&
        ballX - ballSize / 2 <= p2Right &&
        ballY + ballSize / 2 >= p2Top &&
        ballY - ballSize / 2 <= p2Bottom) {
      ballX = p2Left - ballSize / 2;
      _baseSpeed += 15;
      final hitRatio = (ballY - paddle2Y) / (paddleHeight / 2);
      final angle = hitRatio * (pi / 4);
      ballVX = -cos(angle) * _baseSpeed;
      ballVY = sin(angle) * _baseSpeed;
    }

    // --- Scoring ---
    if (ballX < -ballSize) {
      stopBall();
      return 2; // Player 2 scores
    }
    if (ballX > fieldWidth + ballSize) {
      stopBall();
      return 1; // Player 1 scores
    }

    return 0;
  }

  /// Serialize current state to a map for network transmission.
  Map<String, dynamic> toState() => {
        'p1Y': paddle1Y,
        'p2Y': paddle2Y,
        'bX': ballX,
        'bY': ballY,
        'bVX': ballVX,
        'bVY': ballVY,
        's1': scoreP1,
        's2': scoreP2,
      };

  /// Apply state received from host.
  void applyState(Map<String, dynamic> state) {
    paddle1Y = (state['p1Y'] as num).toDouble();
    paddle2Y = (state['p2Y'] as num).toDouble();
    ballX = (state['bX'] as num).toDouble();
    ballY = (state['bY'] as num).toDouble();
    ballVX = (state['bVX'] as num).toDouble();
    ballVY = (state['bVY'] as num).toDouble();
    scoreP1 = (state['s1'] as num).toInt();
    scoreP2 = (state['s2'] as num).toInt();
  }
}
