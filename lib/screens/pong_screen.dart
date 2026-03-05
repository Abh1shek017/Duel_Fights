import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../game/pong_engine.dart';
import '../network/game_server.dart';
import '../network/game_client.dart';
import '../network/messages.dart';

class PongScreen extends StatefulWidget {
  final bool isHost;
  final GameServer? server;
  final GameClient? client;

  const PongScreen({
    super.key,
    required this.isHost,
    this.server,
    this.client,
  });

  @override
  State<PongScreen> createState() => _PongScreenState();
}

class _PongScreenState extends State<PongScreen>
    with SingleTickerProviderStateMixin {
  late PongEngine _engine;
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  StreamSubscription? _networkSub;

  // Touch tracking
  double? _touchStartY;
  double? _paddleStartY;

  // Countdown
  int _countdown = 3;
  bool _gameStarted = false;

  // Score flash
  String? _flashText;
  double _flashOpacity = 0;

  @override
  void initState() {
    super.initState();
    _engine = PongEngine(fieldWidth: 800, fieldHeight: 500);

    _ticker = createTicker(_onTick);

    if (widget.isHost) {
      _listenHost();
      _startCountdown();
    } else {
      _listenClient();
    }
  }

  void _listenHost() {
    _networkSub = widget.server!.onMessage.listen((msg) {
      if (msg.type == MessageType.paddleInput) {
        _engine.paddle2Y = (msg.data['y'] as num).toDouble();
      }
    });
  }

  void _listenClient() {
    _networkSub = widget.client!.onMessage.listen((msg) {
      if (msg.type == MessageType.gameState) {
        _engine.applyState(msg.data);
      } else if (msg.type == MessageType.startGame) {
        _startCountdown();
      } else if (msg.type == MessageType.scoreUpdate) {
        _showScoreFlash(msg.data['text'] as String);
      }
    });
  }

  void _startCountdown() {
    // Notify client to start countdown too
    if (widget.isHost) {
      widget.server!.send(NetworkMessage(
        type: MessageType.startGame,
        data: {},
      ));
    }

    setState(() => _countdown = 3);

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        _gameStarted = true;
        if (widget.isHost) {
          _engine.resetBall(direction: 1);
        }
        _ticker.start();
      }
    });
  }

  void _onTick(Duration elapsed) {
    final dt = (_lastElapsed == Duration.zero)
        ? 1 / 60
        : (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    if (widget.isHost) {
      final scorer = _engine.update(dt.toDouble());

      // Broadcast state
      widget.server!.send(NetworkMessage(
        type: MessageType.gameState,
        data: _engine.toState(),
      ));

      if (scorer != 0) {
        if (scorer == 1) _engine.scoreP1++;
        if (scorer == 2) _engine.scoreP2++;

        final text = scorer == 1 ? 'Player 1 Scores!' : 'Player 2 Scores!';
        _showScoreFlash(text);
        widget.server!.send(NetworkMessage(
          type: MessageType.scoreUpdate,
          data: {'text': text},
        ));

        // Check for match win (first to 5)
        if (_engine.scoreP1 >= 5 || _engine.scoreP2 >= 5) {
          final winner = _engine.scoreP1 >= 5 ? 'Player 1' : 'Player 2';
          _showScoreFlash('$winner WINS!');
          widget.server!.send(NetworkMessage(
            type: MessageType.scoreUpdate,
            data: {'text': '$winner WINS!'},
          ));
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              _engine.scoreP1 = 0;
              _engine.scoreP2 = 0;
              _engine.resetBall(direction: 1);
            }
          });
        } else {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _engine.resetBall(direction: scorer == 1 ? -1 : 1);
            }
          });
        }
      }
    } else {
      // Client: send paddle input
      widget.client!.send(NetworkMessage(
        type: MessageType.paddleInput,
        data: {'y': _engine.paddle2Y},
      ));
    }

    setState(() {});
  }

  void _showScoreFlash(String text) {
    setState(() {
      _flashText = text;
      _flashOpacity = 1.0;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _flashOpacity = 0);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _networkSub?.cancel();
    widget.server?.dispose();
    widget.client?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: LayoutBuilder(builder: (context, constraints) {
        final scaleX = constraints.maxWidth / _engine.fieldWidth;
        final scaleY = constraints.maxHeight / _engine.fieldHeight;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final offsetX = (constraints.maxWidth - _engine.fieldWidth * scale) / 2;
        final offsetY =
            (constraints.maxHeight - _engine.fieldHeight * scale) / 2;

        return GestureDetector(
          onPanStart: (d) {
            _touchStartY = d.localPosition.dy;
            if (widget.isHost) {
              _paddleStartY = _engine.paddle1Y;
            } else {
              _paddleStartY = _engine.paddle2Y;
            }
          },
          onPanUpdate: (d) {
            if (_touchStartY == null || _paddleStartY == null) return;
            final deltaY = (d.localPosition.dy - _touchStartY!) / scale;
            final newY = (_paddleStartY! + deltaY)
                .clamp(PongEngine.paddleHeight / 2,
                    _engine.fieldHeight - PongEngine.paddleHeight / 2);
            if (widget.isHost) {
              _engine.paddle1Y = newY;
            } else {
              _engine.paddle2Y = newY;
            }
          },
          child: Stack(
            children: [
              // ── Game Canvas ──
              CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _PongPainter(
                  engine: _engine,
                  scale: scale,
                  offsetX: offsetX,
                  offsetY: offsetY,
                ),
              ),

              // ── Score HUD ──
              Positioned(
                top: offsetY + 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _scoreBox('P1', _engine.scoreP1, Colors.cyanAccent),
                    const SizedBox(width: 40),
                    Text('—',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 28)),
                    const SizedBox(width: 40),
                    _scoreBox('P2', _engine.scoreP2, Colors.purpleAccent),
                  ],
                ),
              ),

              // ── Countdown ──
              if (!_gameStarted)
                Center(
                  child: Text(
                    _countdown > 0 ? '$_countdown' : 'GO!',
                    style: TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                            color: Colors.cyanAccent, blurRadius: 30),
                      ],
                    ),
                  ),
                ),

              // ── Score Flash ──
              if (_flashText != null)
                Center(
                  child: AnimatedOpacity(
                    opacity: _flashOpacity,
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      _flashText!,
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: Colors.yellowAccent,
                        shadows: [
                          Shadow(color: Colors.orange, blurRadius: 20),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Role indicator ──
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Text(
                  widget.isHost
                      ? 'You are HOST (left paddle) — drag to move'
                      : 'You are CLIENT (right paddle) — drag to move',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _scoreBox(String label, int score, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 14,
                letterSpacing: 4)),
        Text(
          '$score',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            color: color,
            shadows: [Shadow(color: color, blurRadius: 12)],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Custom Painter for the Pong field
// ─────────────────────────────────────────────
class _PongPainter extends CustomPainter {
  final PongEngine engine;
  final double scale;
  final double offsetX;
  final double offsetY;

  _PongPainter({
    required this.engine,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Field background
    final fieldRect = Rect.fromLTWH(
        offsetX, offsetY, engine.fieldWidth * scale, engine.fieldHeight * scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fieldRect, const Radius.circular(12)),
      Paint()..color = const Color(0xFF111633),
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(fieldRect, const Radius.circular(12)),
      Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Center dashed line
    final centerX = offsetX + engine.fieldWidth * scale / 2;
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 2;
    for (double y = offsetY; y < offsetY + engine.fieldHeight * scale; y += 16) {
      canvas.drawLine(Offset(centerX, y), Offset(centerX, y + 8), dashPaint);
    }

    // Paddle 1 (left, cyan)
    _drawPaddle(canvas, engine.paddle1Y, PongEngine.paddleMargin,
        Colors.cyanAccent);

    // Paddle 2 (right, purple)
    _drawPaddle(
        canvas,
        engine.paddle2Y,
        engine.fieldWidth - PongEngine.paddleMargin - PongEngine.paddleWidth,
        Colors.purpleAccent);

    // Ball
    final bx = offsetX + engine.ballX * scale;
    final by = offsetY + engine.ballY * scale;
    final br = PongEngine.ballSize / 2 * scale;

    // Glow
    canvas.drawCircle(
      Offset(bx, by),
      br * 3,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );
    // Ball body
    canvas.drawCircle(
      Offset(bx, by),
      br,
      Paint()..color = Colors.white,
    );
  }

  void _drawPaddle(Canvas canvas, double paddleY, double paddleX, Color color) {
    final x = offsetX + paddleX * scale;
    final y = offsetY + (paddleY - PongEngine.paddleHeight / 2) * scale;
    final w = PongEngine.paddleWidth * scale;
    final h = PongEngine.paddleHeight * scale;

    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h), Radius.circular(w / 2));

    // Glow
    canvas.drawRRect(
      rect.inflate(4),
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Body
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PongPainter old) => true;
}
