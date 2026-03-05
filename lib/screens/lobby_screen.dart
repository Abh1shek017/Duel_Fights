import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nearby_connections/nearby_connections.dart';
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
  late final AnimationController _pulseController;

  String _status = '';
  bool _connecting = false;

  bool _isDiscovering = false;
  final Map<String, String> _discoveredDevices = {};

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
    _pulseController.dispose();
    if (_isDiscovering) {
      Nearby().stopDiscovery();
    }
    super.dispose();
  }

  void _updateStatus(String message, {bool connecting = false}) {
    if (mounted) {
      setState(() {
        _status = message;
        _connecting = connecting;
      });
    }
  }

  Future<bool> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();

    // Not all permissions are granted on every OS version (e.g. Android 11 vs 12).
    // The most important ones are location and bluetooth basic.
    if (await Permission.location.isGranted) {
      return true;
    }
    return false;
  }

  Future<void> _hostGame() async {
    bool hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      _updateStatus('Requires Location & Bluetooth permissions.');
      return;
    }

    _updateStatus('Advertising server...', connecting: true);
    setState(() {
      _isDiscovering = false;
      _discoveredDevices.clear();
    });

    final server = GameServer();
    try {
      await server.start();

      if (!mounted) return;

      _updateStatus('Hosting! Waiting for players...');

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GameSelectionScreen(server: server),
          ),
        );
      }
    } catch (e) {
      _updateStatus('Failed to host: $e');
    }
  }

  Future<void> _startDiscovery() async {
    bool hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      _updateStatus('Requires Location & Bluetooth permissions.');
      return;
    }

    setState(() {
      _isDiscovering = true;
      _discoveredDevices.clear();
    });

    _updateStatus('Scanning for hosts...', connecting: true);

    try {
      // Always ensure we aren't already discovering to prevent PlatformException
      await Nearby().stopDiscovery();
      
      await Nearby().startDiscovery(
        "Brawlers Player",
        Strategy.P2P_STAR,
        onEndpointFound: (String id, String userName, String serviceId) {
          if (serviceId == "com.brawlers.bluetooth_brawlers") {
            setState(() {
              _discoveredDevices[id] = userName;
            });
          }
        },
        onEndpointLost: (String? id) {
          if (id != null) {
            setState(() {
              _discoveredDevices.remove(id);
            });
          }
        },
        serviceId: "com.brawlers.bluetooth_brawlers",
      );
    } catch (e) {
      _updateStatus('Failed to start scanning: $e');
      setState(() => _isDiscovering = false);
    }
  }

  Future<void> _connectToHost(String endpointId) async {
    Nearby().stopDiscovery();
    setState(() => _isDiscovering = false);

    _updateStatus('Connecting...', connecting: true);

    final client = GameClient();
    final success = await client.connect(endpointId, 8080); // port unused

    if (!mounted) return;

    if (!success) {
      _updateStatus('Connection rejected or failed.');
      return;
    }

    _updateStatus('Connected! Waiting for host to select game...');

    client.onMessage
        .firstWhere((msg) => msg.type == MessageType.gameSelected)
        .then((msg) {
          if (!mounted) return;

          final gameType = GameType.values.byName(
            msg.data['gameType'] as String,
          );

          if (gameType == GameType.pong) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => PongScreen(isHost: false, client: client),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Host selected an unimplemented game!'),
              ),
            );
            _updateStatus('Disconnected.');
            client.dispose();
          }
        });
  }

  void _testOffline() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PongScreen(isHost: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final h = size.height;
    final w = size.width;

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
                      _AnimatedTitle(
                        pulseController: _pulseController,
                        height: h,
                      ),
                      SizedBox(height: h * 0.01),
                      Text(
                        'OFFLINE MULTIPLAYER BRAWLS',
                        style: TextStyle(
                          fontSize: (h * 0.016).clamp(10.0, 16.0),
                          color: Colors.cyanAccent.withValues(alpha: 0.7),
                          letterSpacing: 6,
                        ),
                      ),
                      const Spacer(flex: 2),
                      _ActionButtons(
                        height: h,
                        width: w,
                        isConnecting: _connecting && !_isDiscovering,
                        onHost: _hostGame,
                        onJoin: _startDiscovery,
                      ),
                      SizedBox(height: h * 0.02),
                      // Replace IP Input with Discovery List
                      if (_isDiscovering)
                        _DiscoveryList(
                          height: h,
                          devices: _discoveredDevices,
                          onConnect: _connectToHost,
                        ),
                      SizedBox(height: h * 0.02),
                      FractionallySizedBox(
                        widthFactor: 0.5,
                        child: _NeonButton(
                          label: 'TEST OFFLINE',
                          icon: Icons.play_arrow,
                          color: Colors.greenAccent,
                          height: h,
                          onTap: _testOffline,
                        ),
                      ),
                      const Spacer(flex: 4),
                    ],
                  ),
                ),
              ),
            ),
            _StatusIndicator(status: _status, isConnecting: _connecting),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryList extends StatelessWidget {
  final double height;
  final Map<String, String> devices;
  final Function(String) onConnect;

  const _DiscoveryList({
    required this.height,
    required this.devices,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: (height * 0.2).clamp(100.0, 200.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
        color: Colors.white.withValues(alpha: 0.05),
      ),
      child: devices.isEmpty
          ? Center(
              child: Text(
                "Looking for Brawlers...",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            )
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                String id = devices.keys.elementAt(index);
                String name = devices[id]!;
                return ListTile(
                  leading: const Icon(
                    Icons.phone_android,
                    color: Colors.cyanAccent,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    id,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.purpleAccent,
                    size: 16,
                  ),
                  onTap: () => onConnect(id),
                );
              },
            ),
    );
  }
}

class _AnimatedTitle extends AnimatedWidget {
  final double height;

  const _AnimatedTitle({
    required AnimationController pulseController,
    required this.height,
  }) : super(listenable: pulseController);

  @override
  Widget build(BuildContext context) {
    final value = (listenable as AnimationController).value;
    final glow = 4 + value * 12;

    return Text(
      '⚡ BLUETOOTH\n   BRAWLERS ⚡',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: (height * 0.042).clamp(28.0, 44.0),
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
  }
}

class _ActionButtons extends StatelessWidget {
  final double height;
  final double width;
  final bool isConnecting;
  final VoidCallback onHost;
  final VoidCallback onJoin;

  const _ActionButtons({
    required this.height,
    required this.width,
    required this.isConnecting,
    required this.onHost,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NeonButton(
            label: 'HOST GAMES',
            icon: Icons.sensors,
            color: Colors.cyanAccent,
            height: height,
            onTap: isConnecting ? null : onHost,
          ),
        ),
        SizedBox(width: width * 0.04), // responsive gap
        Expanded(
          child: _NeonButton(
            label: 'JOIN GAMES',
            icon: Icons.sports_esports,
            color: Colors.purpleAccent,
            height: height,
            onTap: isConnecting ? null : onJoin,
          ),
        ),
      ],
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final String status;
  final bool isConnecting;

  const _StatusIndicator({required this.status, required this.isConnecting});

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);

    return Positioned(
      bottom: size.height * 0.03,
      left: size.width * 0.03,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.03,
          vertical: size.height * 0.015,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isConnecting) ...[
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
              status,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: (size.height * 0.015).clamp(10.0, 14.0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeonButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double height;
  final VoidCallback? onTap;

  const _NeonButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final buttonFontSize = (height * 0.02).clamp(14.0, 20.0);

    return SizedBox(
      height: (height * 0.065).clamp(44.0, 60.0),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: buttonFontSize * 1.2),
        label: Text(
          label,
          style: TextStyle(
            fontSize: buttonFontSize,
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
