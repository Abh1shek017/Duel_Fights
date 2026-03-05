import 'dart:async';
import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart';
import 'messages.dart';

class GameServer {
  final String _serviceId = "com.brawlers.bluetooth_brawlers";
  final String _hostName = "Brawlers Host";
  final Strategy _strategy = Strategy.P2P_STAR;

  final StreamController<NetworkMessage> _messageController =
      StreamController<NetworkMessage>.broadcast();
  Stream<NetworkMessage> get onMessage => _messageController.stream;

  final Completer<void> _clientConnected = Completer<void>();
  Future<void> get clientConnected => _clientConnected.future;

  String? _clientEndpointId;
  String _messageBuffer = '';

  GameServer();

  Future<void> start() async {
    try {
      await Nearby().startAdvertising(
        _hostName,
        _strategy,
        onConnectionInitiated: _handleConnectionInitiated,
        onConnectionResult: _handleConnectionResult,
        onDisconnected: _handleDisconnected,
        serviceId: _serviceId,
      );
    } catch (e) {
      throw Exception("Failed to start advertising: $e");
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
      _clientEndpointId = id;
      if (!_clientConnected.isCompleted) {
        _clientConnected.complete();
      }
      Nearby().stopAdvertising();
    }
  }

  void _handleDisconnected(String id) {
    if (_clientEndpointId == id) {
      _clientEndpointId = null;
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
    if (_clientEndpointId == null) return;

    final payloadBytes = Uint8List.fromList(message.encode().codeUnits);
    Nearby().sendBytesPayload(_clientEndpointId!, payloadBytes);
  }

  Future<String> getLocalIP() async {
    // Placeholder to satisfy existing UI code.
    return 'NEARBY_HOST';
  }

  Future<void> dispose() async {
    if (_clientEndpointId != null) {
      Nearby().disconnectFromEndpoint(_clientEndpointId!);
    }
    await Nearby().stopAdvertising();
    await _messageController.close();
  }
}
