import 'package:flutter/material.dart';
import '../network/game_server.dart';
import '../network/game_client.dart';
import 'pong_screen.dart';
import 'game_selection_screen.dart';
import '../game/games_registry.dart';
import '../network/messages.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _ipController = TextEditingController(
    text: '127.0.0.1',
  );

  late AnimationController _pulseController;

  String _status = '';
  String _localIP = '';
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ipController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _hostGame() async {
    setState(() {
      _connecting = true;
      _status = 'Starting server...';
    });

    final server = GameServer();
    try {
      await server.start();
      final ip = await server.getLocalIP();

      if (!mounted) return;

      setState(() {
        _localIP = ip;
        _status = 'Hosting on $ip:8080';
        _connecting = false;
      });

      // Navigate to game selection screen
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GameSelectionScreen(server: server)),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status = 'Failed to host: $e';
        _connecting = false;
      });
    }
  }

  Future<void> _joinGame() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    setState(() {
      _connecting = true;
      _status = 'Connecting to $ip...';
    });

    final client = GameClient();
    final success = await client.connect(ip, 8080);

    if (!mounted) return;

    if (success) {
      setState(() {
        _status = 'Connected! Waiting for host to select game...';
      });

      // Listen for the first message which should be gameSelected
      client.onMessage
          .firstWhere((msg) => msg.type == MessageType.gameSelected)
          .then((msg) {
            if (!mounted) return;

            final gameTypeStr = msg.data['gameType'] as String;
            final gameType = GameType.values.byName(gameTypeStr);

            if (gameType == GameType.pong) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => PongScreen(isHost: false, client: client),
                ),
              );
            } else {
              // Fallback for unimplemented games on client side
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Host selected an unimplemented game!'),
                ),
              );
              setState(() {
                _status = 'Disconnected.';
                _connecting = false;
              });
              client.dispose();
            }
          });
    } else {
      setState(() {
        _status = 'Connection failed. Is the host running?';
        _connecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;

    // Responsive styling
    final titleFontSize = (h * 0.042).clamp(28.0, 44.0);
    final subtitleFontSize = (h * 0.016).clamp(10.0, 16.0);
    final buttonFontSize = (h * 0.02).clamp(14.0, 20.0);
    final inputFontSize = (h * 0.02).clamp(14.0, 20.0);
    final statusFontSize = (h * 0.015).clamp(10.0, 14.0);
    final buttonHeight = (h * 0.065).clamp(44.0, 60.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.04,
                    vertical: h * 0.02,
                  ),
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      _buildTitle(titleFontSize),
                      SizedBox(height: h * 0.01),
                      Text(
                        'LOCAL MULTIPLAYER PONG',
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          color: Colors.cyanAccent.withValues(alpha: 0.7),
                          letterSpacing: 6,
                        ),
                      ),
                      const Spacer(flex: 2),
                      _buildActionButtons(w, buttonHeight, buttonFontSize),
                      SizedBox(height: h * 0.02),
                      _buildIPInput(buttonHeight, inputFontSize),
                      SizedBox(height: h * 0.02),
                      FractionallySizedBox(
                        widthFactor: 0.5,
                        child: _buildNeonButton(
                          label: 'TEST OFFLINE',
                          icon: Icons.play_arrow,
                          color: Colors.greenAccent,
                          height: buttonHeight,
                          fontSize: buttonFontSize,
                          onTap: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const PongScreen(isHost: true),
                              ),
                            );
                          },
                        ),
                      ),
                      const Spacer(flex: 4),
                    ],
                  ),
                ),
              ),
            ),
            _buildStatusIndicator(h, w, statusFontSize),
            _buildLocalIPIndicator(h, w, statusFontSize),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(double fontSize) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glow = 4 + _pulseController.value * 12;
        return Text(
          '⚡ BLUETOOTH\n   BRAWLERS ⚡',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.cyanAccent.withValues(alpha: 0.8),
                blurRadius: glow,
              ),
              Shadow(
                color: Colors.purpleAccent.withValues(alpha: 0.5),
                blurRadius: glow * 1.5,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(
    double screenWidth,
    double buttonHeight,
    double buttonFontSize,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildNeonButton(
            label: 'HOST GAMES',
            icon: Icons.sensors,
            color: Colors.cyanAccent,
            onTap: _connecting ? null : _hostGame,
            height: buttonHeight,
            fontSize: buttonFontSize,
          ),
        ),
        SizedBox(width: screenWidth * 0.04), // responsive gap
        Expanded(
          child: _buildNeonButton(
            label: 'JOIN GAMES',
            icon: Icons.sports_esports,
            color: Colors.purpleAccent,
            onTap: _connecting ? null : _joinGame,
            height: buttonHeight,
            fontSize: buttonFontSize,
          ),
        ),
      ],
    );
  }

  Widget _buildIPInput(double buttonHeight, double inputFontSize) {
    return FractionallySizedBox(
      widthFactor: 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: TextField(
          controller: _ipController,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: inputFontSize,
            letterSpacing: 2,
          ),
          decoration: InputDecoration(
            hintText: 'Host IP address',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              vertical: buttonHeight * 0.25,
              horizontal: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(double h, double w, double fontSize) {
    if (_status.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: h * 0.03,
      left: w * 0.03,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.03,
          vertical: h * 0.015,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_connecting) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.cyanAccent,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              _status,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: fontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalIPIndicator(double h, double w, double fontSize) {
    if (_localIP.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: h * 0.03,
      right: w * 0.03,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.03,
          vertical: h * 0.015,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: SelectableText(
          'Your IP: $_localIP',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildNeonButton({
    required String label,
    required IconData icon,
    required Color color,
    required double height,
    required double fontSize,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: height,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: fontSize * 1.2),
        label: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: color,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
