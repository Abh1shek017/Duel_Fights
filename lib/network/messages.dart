import 'dart:convert';

/// All message types exchanged between host and client.
enum MessageType {
  startGame,
  paddleInput,
  gameState,
  scoreUpdate,
}

class NetworkMessage {
  final MessageType type;
  final Map<String, dynamic> data;

  NetworkMessage({required this.type, required this.data});

  String encode() {
    return jsonEncode({'type': type.name, 'data': data}) + '\n';
  }

  static NetworkMessage decode(String raw) {
    final map = jsonDecode(raw.trim());
    return NetworkMessage(
      type: MessageType.values.byName(map['type']),
      data: Map<String, dynamic>.from(map['data']),
    );
  }
}
