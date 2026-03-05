import 'dart:async';
import 'dart:io';
import 'messages.dart';

/// TCP client that connects to the host server.
class GameClient {
  Socket? _socket;
  final StreamController<NetworkMessage> _messageController =
      StreamController<NetworkMessage>.broadcast();

  Stream<NetworkMessage> get onMessage => _messageController.stream;

  String _buffer = '';

  Future<bool> connect(String host, int port) async {
    try {
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));
      _socket!.listen(
        (data) {
          _buffer += String.fromCharCodes(data);
          _processBuffer();
        },
        onDone: () {
          _socket = null;
        },
      );
      return true;
    } catch (e) {
      return false;
    }
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
    _socket?.write(message.encode());
  }

  Future<void> dispose() async {
    _socket?.destroy();
    await _messageController.close();
  }
}
