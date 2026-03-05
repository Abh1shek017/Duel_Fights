import 'dart:math';
import 'package:flutter/material.dart';
import '../network/game_server.dart';
import '../network/messages.dart';
import '../game/games_registry.dart';
import 'pong_screen.dart';

class GameSelectionScreen extends StatefulWidget {
  final GameServer server;

  const GameSelectionScreen({super.key, required this.server});

  @override
  State<GameSelectionScreen> createState() => _GameSelectionScreenState();
}

class _GameSelectionScreenState extends State<GameSelectionScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _gridParamController;
  late AnimationController _pulseController;
  late AnimationController _radarController;

  double _pageValue = 0.0;
  bool _waitingForClient = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.5);
    _pageController.addListener(() {
      setState(() {
        _pageValue = _pageController.page ?? 0.0;
      });
    });

    _gridParamController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _gridParamController.dispose();
    _pulseController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  GameType get _selectedGameType {
    int idx = _pageValue.round().clamp(0, availableGames.length - 1);
    return availableGames[idx].type;
  }

  Color get _currentGridColor {
    int lower = _pageValue.floor().clamp(0, availableGames.length - 1);
    int upper = _pageValue.ceil().clamp(0, availableGames.length - 1);
    double t = _pageValue - lower;
    return Color.lerp(
          availableGames[lower].baseColor,
          availableGames[upper].baseColor,
          t,
        ) ??
        Colors.cyanAccent;
  }

  Future<void> _startGame() async {
    setState(() {
      _waitingForClient = true;
    });

    // Wait for client to connect if they haven't already
    await widget.server.clientConnected;

    if (!mounted) return;

    final gameTypeToStart = _selectedGameType;

    // Tell the client which game to load
    widget.server.send(
      NetworkMessage(
        type: MessageType.gameSelected,
        data: {'gameType': gameTypeToStart.name},
      ),
    );

    // Navigate to the appropriate game screen
    if (gameTypeToStart == GameType.pong) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PongScreen(isHost: true, server: widget.server),
        ),
      );
    } else {
      // Placeholder for other games (Tanks, Shooter)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${gameTypeToStart.name.toUpperCase()} NOT ONLINE YET!',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() {
        _waitingForClient = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    final activeColor = _currentGridColor;

    return Scaffold(
      backgroundColor: const Color(0xFF060913),
      body: Stack(
        children: [
          // Background Animated Grid
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _gridParamController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _PerspectiveGridPainter(
                    progress: _gridParamController.value,
                    color: activeColor,
                  ),
                );
              },
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(h, activeColor),
                if (_waitingForClient)
                  Expanded(child: _buildWaitingScreen(h, w, activeColor))
                else ...[
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: h * 0.05),
                      child: PageView.builder(
                        controller: _pageController,
                        physics: const BouncingScrollPhysics(),
                        itemCount: availableGames.length,
                        itemBuilder: (context, index) {
                          return _buildGameCard(context, index, h, w);
                        },
                      ),
                    ),
                  ),
                  _buildStartButton(h, w, activeColor),
                  SizedBox(height: h * 0.05),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(double h, Color color) {
    return Container(
      height: h * 0.15,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: color),
              onPressed: () {
                widget.server.dispose();
                Navigator.of(context).pop();
              },
            ),
          ),
          Text(
            'CHOOSE ARENA',
            style: TextStyle(
              color: Colors.white,
              fontSize: h * 0.04,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              shadows: [
                Shadow(color: color.withValues(alpha: 0.8), blurRadius: 15),
              ],
            ),
          ),
          SizedBox(width: 48), // Balance for centering
        ],
      ),
    );
  }

  Widget _buildGameCard(BuildContext context, int index, double h, double w) {
    final game = availableGames[index];
    double diff = (index - _pageValue);
    double absDiff = diff.abs();

    // 3D Matrix Math
    double scale = 1.0 - (absDiff * 0.2).clamp(0.0, 0.4);
    double rotationY = diff * 0.6;
    double opacity = (1.0 - absDiff * 0.5).clamp(0.3, 1.0);
    bool isSelected = absDiff < 0.1;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002) // Perspective projection
        ..rotateY(-rotationY) // Rotate towards center
        ..scale(scale),
      child: Opacity(
        opacity: opacity,
        child: GestureDetector(
          onTap: () {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            );
          },
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: w * 0.02),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  game.baseColor.withValues(alpha: isSelected ? 0.3 : 0.05),
                  game.baseColor.withValues(alpha: 0.0),
                ],
              ),
              border: Border.all(
                color: game.baseColor.withValues(alpha: isSelected ? 0.8 : 0.2),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: game.baseColor.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ]
                  : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Stack(
                children: [
                  // Inner tech pattern (optional simple grid)
                  CustomPaint(
                    size: Size.infinite,
                    painter: _TechPatternPainter(color: game.baseColor),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: EdgeInsets.all(
                          isSelected ? h * 0.03 : h * 0.01,
                        ),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: game.baseColor.withValues(
                            alpha: isSelected ? 0.2 : 0.05,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: game.baseColor.withValues(alpha: 0.5),
                                blurRadius: 20,
                              ),
                          ],
                        ),
                        child: Icon(
                          game.icon,
                          size: h * 0.12,
                          color: isSelected ? Colors.white : game.baseColor,
                        ),
                      ),
                      SizedBox(height: h * 0.05, width: double.infinity),
                      Text(
                        game.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: h * 0.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          shadows: [
                            if (isSelected)
                              Shadow(color: game.baseColor, blurRadius: 10),
                          ],
                        ),
                      ),
                      SizedBox(height: h * 0.01),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: game.baseColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: game.baseColor.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          game.subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: h * 0.016,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton(double h, double w, Color color) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glow = 5 + _pulseController.value * 25;
        return Container(
          height: h * 0.12,
          width: w * 0.4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: glow,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _startGame,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A0E21),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(40),
                side: BorderSide(color: color, width: 2),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.power_settings_new, color: color, size: h * 0.04),
                SizedBox(width: w * 0.02),
                Text(
                  'INITIALIZE',
                  style: TextStyle(
                    fontSize: h * 0.03,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: Colors.white,
                    shadows: [Shadow(color: color, blurRadius: 10)],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaitingScreen(double h, double w, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return CustomPaint(
                size: Size(h * 0.25, h * 0.25),
                painter: _RadarPainter(
                  progress: _radarController.value,
                  color: color,
                ),
              );
            },
          ),
          SizedBox(height: h * 0.06),
          Text(
            'BROADCASTING \nSECURE FREQUENCY...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: h * 0.03,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              shadows: [Shadow(color: color, blurRadius: 10)],
            ),
          ),
          SizedBox(height: h * 0.02),
          Text(
            'WAITING FOR DEVICE PAIRING',
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: h * 0.015,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── CUSTOM PAINTERS ──

class _PerspectiveGridPainter extends CustomPainter {
  final double progress;
  final Color color;

  _PerspectiveGridPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 2;

    final horizon = size.height * 0.4;
    final w = size.width;
    final h = size.height;

    // Center focal point
    final focalX = w / 2;

    // Draw converging vertical lines extending from horizon to bottom
    const numVerts = 30;
    for (int i = -numVerts; i <= numVerts; i++) {
      // The spacing at the bottom is wide, at the horizon it is narrow
      final bottomX = focalX + i * 80.0;
      final topX = focalX + i * 15.0;
      canvas.drawLine(Offset(topX, horizon), Offset(bottomX, h + 100), paint);
    }

    // Draw horizontal moving lines (simulating forward movement)
    // Spacing increases exponentially as y approaches bottom
    for (int i = 0; i < 25; i++) {
      // Base exponential curve
      double coeff = pow(1.25, i + progress).toDouble();
      double y = horizon + (coeff * 2);

      if (y > horizon && y < h) {
        // Fade out lines very close to horizon
        double opacity = ((y - horizon) / 50).clamp(0.0, 1.0);
        final horizPaint = Paint()
          ..color = color.withValues(alpha: 0.2 * opacity)
          ..strokeWidth = 2;
        canvas.drawLine(Offset(0, y), Offset(w, y), horizPaint);
      }
    }

    // Draw horizon glow
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - 50, w, 100),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            color.withValues(alpha: 0.4),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, horizon - 50, w, 100)),
    );
  }

  @override
  bool shouldRepaint(covariant _PerspectiveGridPainter old) {
    return progress != old.progress || color != old.color;
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Rings
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, ringPaint);
    canvas.drawCircle(center, radius * 0.66, ringPaint);
    canvas.drawCircle(center, radius * 0.33, ringPaint);

    // Crosshairs
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      ringPaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      ringPaint,
    );

    // Sweeping beam
    final sweepGradient = SweepGradient(
      colors: [
        Colors.transparent,
        color.withValues(alpha: 0.1),
        color.withValues(alpha: 0.8),
        Colors.transparent,
      ],
      stops: const [0.0, 0.4, 0.95, 1.0],
      transform: GradientRotation(progress * 2 * pi - pi / 2),
    );

    final beamPaint = Paint()
      ..shader = sweepGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

    canvas.drawCircle(center, radius, beamPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      progress != old.progress || color != old.color;
}

class _TechPatternPainter extends CustomPainter {
  final Color color;
  _TechPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TechPatternPainter old) => color != old.color;
}
