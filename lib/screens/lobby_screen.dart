import 'package:flutter/material.dart';
import '../network/game_server.dart';
import '../network/game_client.dart';
import 'pong_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _ipController =
      TextEditingController(text: '127.0.0.1');
  String _status = '';
  bool _connecting = false;
  String _localIP = '';
  late AnimationController _pulseController;

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
      setState(() {
        _localIP = ip;
        _status = 'Hosting on $ip:8080\nWaiting for opponent...';
      });

      await server.clientConnected;

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PongScreen(isHost: true, server: server),
        ),
      );
    } catch (e) {
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PongScreen(isHost: false, client: client),
        ),
      );
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
    final isSmall = h < 700;

    // Clamp font sizes so they look good on both small phones and large screens
    final titleFontSize = (h * 0.042).clamp(28.0, 44.0);
    final subtitleFontSize = (h * 0.016).clamp(10.0, 16.0);
    final buttonFontSize = (h * 0.02).clamp(14.0, 20.0);
    final inputFontSize = (h * 0.02).clamp(14.0, 20.0);
    final statusFontSize = (h * 0.017).clamp(11.0, 16.0);
    final buttonHeight = (h * 0.065).clamp(44.0, 60.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.06,
                vertical: h * 0.02,
              ),
              child: Column(
                children: [
                  // ── Top spacer ──
                  Spacer(flex: isSmall ? 1 : 2),

                  // ── Title ──
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final glow = 4 + _pulseController.value * 12;
                      return Text(
                        '⚡ BLUETOOTH\n   BRAWLERS ⚡',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                                color:
                                    Colors.cyanAccent.withValues(alpha: 0.8),
                                blurRadius: glow),
                            Shadow(
                                color:
                                    Colors.purpleAccent.withValues(alpha: 0.5),
                                blurRadius: glow * 1.5),
                          ],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: h * 0.008),
                  Text(
                    'LOCAL MULTIPLAYER PONG',
                    style: TextStyle(
                      fontSize: subtitleFontSize,
                      color: Colors.cyanAccent.withValues(alpha: 0.7),
                      letterSpacing: 6,
                    ),
                  ),

                  Spacer(flex: isSmall ? 1 : 2),

                  // ── Host Button ──
                  _buildNeonButton(
                    label: 'HOST GAME',
                    icon: Icons.wifi_tethering,
                    color: Colors.cyanAccent,
                    onTap: _connecting ? null : _hostGame,
                    height: buttonHeight,
                    fontSize: buttonFontSize,
                  ),
                  SizedBox(height: h * 0.015),

                  // ── IP Input ──
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.purpleAccent.withValues(alpha: 0.4)),
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: TextField(
                      controller: _ipController,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: inputFontSize,
                          letterSpacing: 2),
                      decoration: InputDecoration(
                        hintText: 'Host IP address',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: h * 0.015, horizontal: 20),
                      ),
                    ),
                  ),
                  SizedBox(height: h * 0.015),

                  // ── Join Button ──
                  _buildNeonButton(
                    label: 'JOIN GAME',
                    icon: Icons.sports_esports,
                    color: Colors.purpleAccent,
                    onTap: _connecting ? null : _joinGame,
                    height: buttonHeight,
                    fontSize: buttonFontSize,
                  ),

                  SizedBox(height: h * 0.025),

                  // ── Status ──
                  if (_status.isNotEmpty)
                    Container(
                      padding: EdgeInsets.all(h * 0.012),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_connecting)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.cyanAccent),
                            ),
                          if (_connecting) const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _status,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: statusFontSize,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_localIP.isNotEmpty) ...[
                    SizedBox(height: h * 0.012),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 20, vertical: h * 0.01),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(colors: [
                          Colors.cyanAccent.withValues(alpha: 0.1),
                          Colors.purpleAccent.withValues(alpha: 0.1),
                        ]),
                      ),
                      child: SelectableText(
                        'Your IP: $_localIP',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: inputFontSize,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],

                  // ── Bottom spacer ──
                  const Spacer(flex: 3),
                ],
              ),
            ),
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
      width: double.infinity,
      height: height,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: fontSize * 1.1),
        label: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
            color: color,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
