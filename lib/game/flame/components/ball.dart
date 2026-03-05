import 'dart:ui';
import 'package:flame/components.dart';
import '../../pong_engine.dart';

class PongBall extends PositionComponent {
  final PongEngine engine;

  PongBall(this.engine)
    : super(size: Vector2.all(PongEngine.ballSize), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    // Sync position from authoritative engine
    position.setValues(engine.ballX, engine.ballY);
  }

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();
    // Inner center point
    final center = Offset(rect.width / 2, rect.height / 2);

    // Subtle bloom aura
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: rect.width * 2,
        height: rect.height * 2,
      ),
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Solid core
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rect.width, height: rect.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }
}
