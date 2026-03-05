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

  const PongScreen({super.key, required this.isHost, this.server, this.client});

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

  // Countdown & State
  int _countdown = 3;
  bool _gameStarted = false;
  bool _isPaused = false;

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
    _networkSub = widget.server?.onMessage.listen((msg) {
      if (msg.type == MessageType.paddleInput) {
        _engine.paddle2Y = (msg.data['y'] as num).toDouble();
      } else if (msg.type == MessageType.gamePaused) {
        setState(() => _isPaused = true);
      } else if (msg.type == MessageType.gameResumed) {
        setState(() => _isPaused = false);
      }
    });
  }

  void _listenClient() {
    _networkSub = widget.client?.onMessage.listen((msg) {
      if (msg.type == MessageType.gameState) {
        _engine.applyState(msg.data);
      } else if (msg.type == MessageType.startGame) {
        _startCountdown();
      } else if (msg.type == MessageType.scoreUpdate) {
        _showScoreFlash(msg.data['text'] as String);
      } else if (msg.type == MessageType.gamePaused) {
        setState(() => _isPaused = true);
      } else if (msg.type == MessageType.gameResumed) {
        setState(() => _isPaused = false);
      }
    });
  }

  void _startCountdown() {
    // Notify client to start countdown too
    if (widget.isHost) {
      widget.server?.send(
        NetworkMessage(type: MessageType.startGame, data: {}),
      );
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
    if (_isPaused || !_gameStarted) {
      _lastElapsed = elapsed;
      return;
    }

    final dt = (_lastElapsed == Duration.zero)
        ? 1 / 60
        : (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    if (widget.isHost) {
      final scorer = _engine.update(dt.toDouble());

      // Broadcast state
      widget.server?.send(
        NetworkMessage(type: MessageType.gameState, data: _engine.toState()),
      );

      if (scorer != 0) {
        if (scorer == 1) _engine.scoreP1++;
        if (scorer == 2) _engine.scoreP2++;

        final text = scorer == 1 ? 'Player 1 Scores!' : 'Player 2 Scores!';
        _showScoreFlash(text);
        widget.server?.send(
          NetworkMessage(type: MessageType.scoreUpdate, data: {'text': text}),
        );

        // Check for match win (first to 5)
        if (_engine.scoreP1 >= 5 || _engine.scoreP2 >= 5) {
          final winner = _engine.scoreP1 >= 5 ? 'Player 1' : 'Player 2';
          _showScoreFlash('$winner WINS!');
          widget.server?.send(
            NetworkMessage(
              type: MessageType.scoreUpdate,
              data: {'text': '$winner WINS!'},
            ),
          );
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
      widget.client?.send(
        NetworkMessage(
          type: MessageType.paddleInput,
          data: {'y': _engine.paddle2Y},
        ),
      );
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

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
    final msgType = _isPaused
        ? MessageType.gamePaused
        : MessageType.gameResumed;
    if (widget.isHost) {
      widget.server?.send(NetworkMessage(type: msgType, data: {}));
    } else {
      widget.client?.send(NetworkMessage(type: msgType, data: {}));
    }
  }

  void _quitGame() {
    if (widget.isHost) {
      widget.server?.dispose();
    } else {
      widget.client?.dispose();
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
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
      backgroundColor: const Color(0xFF050510),
      body: Stack(
        children: [
          // ── Background Grid & Scanlines ──
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: CustomPaint(painter: _SynthwaveBackgroundPainter()),
            ),
          ),

          LayoutBuilder(
            builder: (context, constraints) {
              final scaleX = constraints.maxWidth / _engine.fieldWidth;
              final scaleY = constraints.maxHeight / _engine.fieldHeight;
              final scale = scaleX < scaleY ? scaleX : scaleY;
              final offsetX =
                  (constraints.maxWidth - _engine.fieldWidth * scale) / 2;
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
                  final newY = (_paddleStartY! + deltaY).clamp(
                    PongEngine.paddleHeight / 2,
                    _engine.fieldHeight - PongEngine.paddleHeight / 2,
                  );
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
                      top: offsetY + 24,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _scoreBox(
                            'HOST',
                            _engine.scoreP1,
                            const Color(0xFF00FFCC),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'VS',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                color: Colors.white.withValues(alpha: 0.2),
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          _scoreBox(
                            'CLIENT',
                            _engine.scoreP2,
                            const Color(0xFFFF00FF),
                          ),
                        ],
                      ),
                    ),

                    // ── Countdown ──
                    if (!_gameStarted)
                      Center(
                        child: Text(
                          _countdown > 0 ? '0$_countdown' : 'FIGHT!',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: _countdown > 0 ? 120 : 80,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: const Color(
                                  0xFFFF00FF,
                                ).withValues(alpha: 0.8),
                                blurRadius: 40,
                              ),
                              Shadow(
                                color: const Color(
                                  0xFF00FFCC,
                                ).withValues(alpha: 0.8),
                                blurRadius: 20,
                              ),
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
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFFFCEE09),
                              letterSpacing: 2,
                              shadows: [
                                Shadow(
                                  color: Color(0xFFFF0055),
                                  blurRadius: 30,
                                  offset: Offset(0, 4),
                                ),
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
                            ? '[ SYSTEM: HOST CTRL ]'
                            : '[ SYSTEM: CLIENT CTRL ]',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 10,
                          letterSpacing: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // ── Top Action Bar (Pause / Exit) ──
                    Positioned(
                      top: offsetY + 24,
                      left: offsetX + 24,
                      child: _buildSynthButton(
                        icon: Icons.close_rounded,
                        onTap: _quitGame,
                        color: const Color(0xFFFF0055),
                      ),
                    ),
                    Positioned(
                      top: offsetY + 24,
                      right: offsetX + 24,
                      child: _buildSynthButton(
                        icon: _isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        onTap: _gameStarted ? _togglePause : null,
                        color: const Color(0xFF00FFCC),
                      ),
                    ),

                    // ── Pause Menu Overlay ──
                    if (_isPaused)
                      Container(
                        color: const Color(0xFF03030A).withValues(alpha: 0.8),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'SYSTEM PAUSED',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 56,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white,
                                  letterSpacing: 4,
                                  shadows: [
                                    Shadow(
                                      color: Color(0xFF00FFCC),
                                      blurRadius: 20,
                                    ),
                                    Shadow(
                                      color: Color(0xFFFF00FF),
                                      blurRadius: 40,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 48),
                              GestureDetector(
                                onTap: _togglePause,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 48,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF00FFCC,
                                    ).withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: const Color(0xFF00FFCC),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF00FFCC,
                                        ).withValues(alpha: 0.3),
                                        blurRadius: 20,
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'RESUME',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 8,
                                      color: Color(0xFF00FFCC),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _scoreBox(String label, int score, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Outfit',
            color: color.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 6,
          ),
        ),
        Text(
          score.toString().padLeft(2, '0'),
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 64,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.1,
            shadows: [
              Shadow(color: color, blurRadius: 24, offset: const Offset(0, 2)),
              Shadow(color: color.withValues(alpha: 0.5), blurRadius: 48),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSynthButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12),
          ],
        ),
        child: Icon(
          icon,
          color: onTap == null ? color.withValues(alpha: 0.3) : color,
          size: 28,
        ),
      ),
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
    final fieldRect = Rect.fromLTWH(
      offsetX,
      offsetY,
      engine.fieldWidth * scale,
      engine.fieldHeight * scale,
    );

    // Deep void background
    canvas.drawRRect(
      RRect.fromRectAndRadius(fieldRect, const Radius.circular(16)),
      Paint()..color = const Color(0xFF03030A),
    );

    // Glowing synthwave border
    final borderPaint = Paint()
      ..color = const Color(0xFF00FFCC).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Outer glow for the border
    canvas.drawRRect(
      RRect.fromRectAndRadius(fieldRect, const Radius.circular(16)).inflate(2),
      Paint()
        ..color = const Color(0xFF00FFCC).withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(fieldRect, const Radius.circular(16)),
      borderPaint,
    );

    // Center divider (Laser Fence)
    final centerX = offsetX + engine.fieldWidth * scale / 2;
    final dashPaint = Paint()
      ..color = const Color(0xFFFF00FF).withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

    for (
      double y = offsetY;
      y < offsetY + engine.fieldHeight * scale;
      y += 24
    ) {
      canvas.drawLine(Offset(centerX, y), Offset(centerX, y + 12), dashPaint);
    }

    // Paddles (Host = Cyan, Client = Magenta)
    _drawPaddle(
      canvas,
      engine.paddle1Y,
      PongEngine.paddleMargin,
      const Color(0xFF00FFCC),
    );
    _drawPaddle(
      canvas,
      engine.paddle2Y,
      engine.fieldWidth - PongEngine.paddleMargin - PongEngine.paddleWidth,
      const Color(0xFFFF00FF),
    );

    // The Plasma Ball
    final bx = offsetX + engine.ballX * scale;
    final by = offsetY + engine.ballY * scale;
    final br = PongEngine.ballSize / 2 * scale;

    // Ball Outer Core Glow
    canvas.drawCircle(
      Offset(bx, by),
      br * 4,
      Paint()
        ..color = const Color(0xFFFCEE09).withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
    // Ball Inner Core Glow
    canvas.drawCircle(
      Offset(bx, by),
      br * 2,
      Paint()
        ..color = const Color(0xFFFCEE09).withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Ball pure white energy center
    canvas.drawCircle(Offset(bx, by), br * 0.8, Paint()..color = Colors.white);
  }

  void _drawPaddle(Canvas canvas, double paddleY, double paddleX, Color color) {
    final x = offsetX + paddleX * scale;
    final y = offsetY + (paddleY - PongEngine.paddleHeight / 2) * scale;
    final w = PongEngine.paddleWidth * scale;
    final h = PongEngine.paddleHeight * scale;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      Radius.circular(w / 2),
    );

    // Primary Aura
    canvas.drawRRect(
      rect.inflate(8),
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Secondary intense glow
    canvas.drawRRect(
      rect.inflate(2),
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Solid Core
    canvas.drawRRect(rect, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PongPainter old) => true;
}

// ─────────────────────────────────────────────
//  Synthwave Background Environment
// ─────────────────────────────────────────────
class _SynthwaveBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF00FF).withValues(alpha: 0.2)
      ..strokeWidth = 1;

    // Draw perspective grid
    final centerY = size.height * 0.6;

    // Horizon line glow
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = const Color(0xFF00FFCC).withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Vertical vanishing lines
    for (double x = -size.width; x <= size.width * 2; x += 40) {
      canvas.drawLine(
        Offset(size.width / 2, centerY),
        Offset(x, size.height),
        paint,
      );
    }

    // Horizontal moving lines (pseudo-perspective)
    for (double y = centerY + 10; y <= size.height; y += (y - centerY) * 0.15) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SynthwaveBackgroundPainter old) => false;
}
