import 'dart:async';
import 'dart:io';
import 'messages.dart';

/// TCP server that listens for a single client connection.
class GameServer {
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final int port;

  final StreamController<NetworkMessage> _messageController =
      StreamController<NetworkMessage>.broadcast();

  Stream<NetworkMessage> get onMessage => _messageController.stream;

  final Completer<void> _clientConnected = Completer<void>();
  Future<void> get clientConnected => _clientConnected.future;

  String _buffer = '';

  GameServer({this.port = 8080});

  Future<void> start() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _serverSocket!.listen((Socket client) {
      _clientSocket = client;
      if (!_clientConnected.isCompleted) {
        _clientConnected.complete();
      }

      client.listen(
        (data) {
          _buffer += String.fromCharCodes(data);
          _processBuffer();
        },
        onDone: () {
          _clientSocket = null;
        },
      );
    });
  }

  void _processBuffer() {
    while (_buffer.contains('\n')) {
      final idx = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx);
      _buffer = _buffer.substring(idx + 1);
      if (line.trim().isNotEmpty) {
        try {
          _messageController.add(NetworkMessage.decode(line));
        } catch (_) {}
      }
    }
  }

  void send(NetworkMessage message) {
    _clientSocket?.write(message.encode());
  }

  Future<String> getLocalIP() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return '127.0.0.1';
  }

  Future<void> dispose() async {
    _clientSocket?.destroy();
    await _serverSocket?.close();
    await _messageController.close();
  }
}
