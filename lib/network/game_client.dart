import 'dart:async';
import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart';
import 'messages.dart';

class GameClient {
  final String _serviceId = "com.brawlers.bluetooth_brawlers";
  final String _clientName = "Brawlers Player";

  final StreamController<NetworkMessage> _messageController =
      StreamController<NetworkMessage>.broadcast();
  Stream<NetworkMessage> get onMessage => _messageController.stream;

  String? _hostEndpointId;
  String _messageBuffer = '';
  Completer<bool>? _connectionCompleter;

  Future<bool> connect(String endpointId, int unusedPort) async {
    _connectionCompleter = Completer<bool>();

    try {
      await Nearby().requestConnection(
        _clientName,
        endpointId,
        onConnectionInitiated: _handleConnectionInitiated,
        onConnectionResult: _handleConnectionResult,
        onDisconnected: _handleDisconnected,
      );

      Nearby().stopDiscovery();

      return await _connectionCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
    } catch (e) {
      return false;
    }
  }

  void _handleConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _messageBuffer += String.fromCharCodes(payload.bytes!);
          _processBuffer();
        }
      },
      onPayloadTransferUpdate: (_, __) {},
    );
  }

  void _handleConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      _hostEndpointId = id;
      _completeConnection(true);
    } else {
      _completeConnection(false);
    }
  }

  void _handleDisconnected(String id) {
    if (_hostEndpointId == id) {
      _hostEndpointId = null;
    }
  }

  void _completeConnection(bool isSuccess) {
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      _connectionCompleter!.complete(isSuccess);
    }
  }

  void _processBuffer() {
    while (_messageBuffer.contains('\n')) {
      final newlineIndex = _messageBuffer.indexOf('\n');
      final messageLine = _messageBuffer.substring(0, newlineIndex).trim();
      _messageBuffer = _messageBuffer.substring(newlineIndex + 1);

      if (messageLine.isNotEmpty) {
        try {
          _messageController.add(NetworkMessage.decode(messageLine));
        } catch (_) {
          // Ignore malformed messages.
        }
      }
    }
  }

  void send(NetworkMessage message) {
    if (_hostEndpointId == null) return;

    final payloadBytes = Uint8List.fromList(message.encode().codeUnits);
    Nearby().sendBytesPayload(_hostEndpointId!, payloadBytes);
  }

  Future<void> dispose() async {
    if (_hostEndpointId != null) {
      Nearby().disconnectFromEndpoint(_hostEndpointId!);
    }
    await Nearby().stopDiscovery();
    await _messageController.close();
  }
}
