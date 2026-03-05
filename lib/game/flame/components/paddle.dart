import 'dart:ui';
import 'package:flame/components.dart';
import '../../pong_engine.dart';

class PongPaddle extends PositionComponent {
  final PongEngine engine;
  final bool isHostPaddle;
  final Color accentColor;

  PongPaddle({
    required this.engine,
    required this.isHostPaddle,
    required this.accentColor,
  }) : super(size: Vector2(PongEngine.paddleWidth, PongEngine.paddleHeight));

  @override
  void update(double dt) {
    super.update(dt);
    if (isHostPaddle) {
      position.setValues(PongEngine.paddleMargin, engine.paddle1Y - size.y / 2);
    } else {
      position.setValues(
        engine.fieldWidth - PongEngine.paddleMargin - PongEngine.paddleWidth,
        engine.paddle2Y - size.y / 2,
      );
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Radius.circular(size.x / 2),
    );

    // Simple blurred shadow
    canvas.drawRRect(
      rect.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Inner glowing aura
    canvas.drawRRect(
      rect.inflate(2),
      Paint()
        ..color = accentColor.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Beautiful white frosted paddle body
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.95),
    );
  }
}
