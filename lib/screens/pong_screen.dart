import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flame/game.dart';

import '../game/flame/pong_game.dart';
import '../game/pong_engine.dart';
import '../network/game_server.dart';
import '../network/game_client.dart';
import '../network/messages.dart';

class PongScreen extends StatefulWidget {
  final bool isHost;
  final GameServer? server;
  final GameClient? client;
  final PongEngine? engine; // Added to allow injecting an engine

  const PongScreen({
    super.key,
    required this.isHost,
    this.server,
    this.client,
    this.engine,
  });

  @override
  State<PongScreen> createState() => _PongScreenState();
}

class _PongScreenState extends State<PongScreen>
    with SingleTickerProviderStateMixin {
  late PongEngine _engine; // Keep engine for direct access to scores etc.
  late Ticker _ticker; // Ticker for UI updates and network sending
  StreamSubscription? _networkSub;

  // Countdown & State
  int _countdown = 3;
  bool _gameStarted = false;
  bool _isPaused = false;

  // Score flash
  String? _flashText;
  double _flashOpacity = 0;

  // Flame game instance
  late final PongGame _pongGame;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? PongEngine(fieldWidth: 800, fieldHeight: 500);

    _pongGame = PongGame(engine: _engine, isHost: widget.isHost);

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
        _pongGame.pauseEngine();
      } else if (msg.type == MessageType.gameResumed) {
        setState(() => _isPaused = false);
        _pongGame.resumeEngine();
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
        _pongGame.pauseEngine();
      } else if (msg.type == MessageType.gameResumed) {
        setState(() => _isPaused = false);
        _pongGame.resumeEngine();
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
        _ticker.start(); // Start ticker for network/UI updates
        _pongGame.startGame(); // Start Flame game loop
      }
    });
  }

  void _onTick(Duration elapsed) {
    if (_isPaused || !_gameStarted) {
      return;
    }

    // The actual game logic update is now handled by PongGame's update method.
    // This _onTick is primarily for network communication and UI updates.

    if (widget.isHost) {
      // Host: Broadcast state and check for scores
      widget.server?.send(
        NetworkMessage(type: MessageType.gameState, data: _engine.toState()),
      );

      // Check for scores from the engine (updated by PongGame)
      final scorer = _pongGame.getAndResetScorer();
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

    // Trigger UI rebuild to show updated scores, etc.
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
    if (_isPaused) {
      _pongGame.pauseEngine();
    } else {
      _pongGame.resumeEngine();
    }

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
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // If deployed uniquely, exit fully.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _networkSub?.cancel();
    widget.server?.dispose();
    widget.client?.dispose();
    _pongGame.pauseEngine(); // Ensure Flame game is paused/stopped
    _pongGame.onRemove(); // Clean up Flame game resources
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Sleek slate dark background
      body: Stack(
        children: [
          // ── Ambient Background ──
          Positioned.fill(
            child: CustomPaint(painter: _AmbientBackgroundPainter()),
          ),

          // ── The Game Area ──
          Positioned.fill(
            child: GameWidget.controlled(gameFactory: () => _pongGame),
          ),

          // ── The UI HUD (Independent of Game Area scaling) ──
          Positioned.fill(
            child: Stack(
              children: [
                // ── Score HUD ──
                Positioned(
                  top: 48,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _scoreBox(
                        'HOST',
                        _engine.scoreP1,
                        const Color(0xFF38BDF8),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Text(
                            'VS',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                      _scoreBox(
                        'CLIENT',
                        _engine.scoreP2,
                        const Color(0xFFF472B6),
                      ),
                    ],
                  ),
                ),

                // ── Countdown ──
                if (!_gameStarted)
                  Center(
                    child: Text(
                      _countdown > 0 ? '$_countdown' : 'PLAY',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: _countdown > 0 ? 120 : 80,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                        letterSpacing: 8,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
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
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Text(
                              _flashText!,
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 36,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Role indicator ──
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Text(
                    widget.isHost
                        ? 'HOST CONTROLS • DRAG LEFT PADDLE'
                        : 'CLIENT CONTROLS • DRAG RIGHT PADDLE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                // ── Top Action Bar (Pause / Exit) ──
                Positioned(
                  top: 48,
                  left: 32,
                  child: _buildGlassButton(
                    icon: Icons.close_rounded,
                    onTap: _quitGame,
                  ),
                ),
                Positioned(
                  top: 48,
                  right: 32,
                  child: _buildGlassButton(
                    icon: _isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    onTap: _gameStarted ? _togglePause : null,
                  ),
                ),

                // ── Pause Menu Overlay ──
                if (_isPaused)
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          color: const Color(0xFF0F172A).withOpacity(0.6),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'PAUSED',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 48,
                                    fontWeight: FontWeight.w300,
                                    color: Colors.white,
                                    letterSpacing: 16,
                                  ),
                                ),
                                const SizedBox(height: 64),
                                GestureDetector(
                                  onTap: _togglePause,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 48,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.2),
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: const Text(
                                      'RESUME',
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 4,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
            color: color.withOpacity(0.8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 4,
          ),
        ),
        Text(
          score.toString(),
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 64,
            fontWeight: FontWeight.w300,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: onTap == null
                  ? Colors.white.withOpacity(0.3)
                  : Colors.white.withOpacity(0.9),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Ambient Glassmorphism Background
// ─────────────────────────────────────────────
class _AmbientBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Soft blurred glowing orbs in the background
    final paint1 = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    final paint2 = Paint()
      ..color = const Color(0xFFC084FC).withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.3),
      size.width * 0.4,
      paint1,
    );
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.7),
      size.width * 0.4,
      paint2,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.9),
      size.width * 0.3,
      paint1,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientBackgroundPainter old) => false;
}
