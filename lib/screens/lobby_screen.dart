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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Title ──
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final glow = 4 + _pulseController.value * 12;
                  return Text(
                    '⚡ BLUETOOTH\n   BRAWLERS ⚡',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                            color: Colors.cyanAccent.withValues(alpha: 0.8),
                            blurRadius: glow),
                        Shadow(
                            color: Colors.purpleAccent.withValues(alpha: 0.5),
                            blurRadius: glow * 1.5),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                'LOCAL MULTIPLAYER PONG',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.cyanAccent.withValues(alpha: 0.7),
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 48),

              // ── Host Button ──
              _buildNeonButton(
                label: 'HOST GAME',
                icon: Icons.wifi_tethering,
                color: Colors.cyanAccent,
                onTap: _connecting ? null : _hostGame,
              ),
              const SizedBox(height: 20),

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
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, letterSpacing: 2),
                  decoration: InputDecoration(
                    hintText: 'Host IP address',
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 20),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Join Button ──
              _buildNeonButton(
                label: 'JOIN GAME',
                icon: Icons.sports_esports,
                color: Colors.purpleAccent,
                onTap: _connecting ? null : _joinGame,
              ),
              const SizedBox(height: 32),

              // ── Status ──
              if (_status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_connecting)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.cyanAccent),
                        ),
                      if (_connecting) const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_localIP.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(colors: [
                      Colors.cyanAccent.withValues(alpha: 0.1),
                      Colors.purpleAccent.withValues(alpha: 0.1),
                    ]),
                  ),
                  child: SelectableText(
                    'Your IP: $_localIP',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNeonButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 18,
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
