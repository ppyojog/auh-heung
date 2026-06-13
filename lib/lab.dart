// 어흥 — Flame 엔진 성능 검증 슬라이스 (/lab).
// 목적: 출시 Flutter 게임이 쓰는 검증된 게임엔진(Flame)이 iOS에서 60fps로 도는지 확인.
// 현재 게임(수제 CustomPaint, 루트 URL)과 같은 렌더러(CanvasKit+로컬wasm)에서 A/B 비교.
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';

const Color _bg = Color(0xFF0B0A12);
const Color _gold = Color(0xFFFFC857);
const Color _goldSoft = Color(0xFFFFE3A0);
const Color _cyan = Color(0xFF53E0E6);
const Color _red = Color(0xFFFF5A57);

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: _bg,
      body: GameWidget(game: AuhHeungLab()),
    ),
  ));
}

// 충돌 콜백의 other는 Flame 버전에 따라 '다른 히트박스' 또는 '다른 컴포넌트'일 수 있어
// 둘 다 안전하게 해석(안 그러면 적이 안 죽는 등 충돌이 조용히 안 먹음).
T? _owner<T>(PositionComponent other) {
  if (other is T) return other as T;
  final p = other.parent;
  return p is T ? p as T : null;
}

class AuhHeungLab extends FlameGame with HasCollisionDetection {
  final Random rng = Random();
  late Player player;
  late JoystickComponent joystick;
  late TextComponent hud;

  double time = 0;
  double spawnT = 0;
  int level = 1, xp = 0, xpNeed = 5, kills = 0;

  @override
  Color backgroundColor() => _bg;

  @override
  Future<void> onLoad() async {
    add(GridBg());
    player = Player()..position = size / 2;
    add(player);

    // 조이스틱 — 엄지존(가운데-오른쪽 하단, 검증된 오른손 엄지 위치)
    joystick = JoystickComponent(
      knob: CircleComponent(radius: 18, paint: Paint()..color = _gold.withOpacity(0.85)),
      background: CircleComponent(radius: 46, paint: Paint()..color = Colors.white.withOpacity(0.10)),
      margin: const EdgeInsets.only(right: 56, bottom: 72),
    );
    add(joystick);

    hud = TextComponent(
      text: '',
      position: Vector2(12, 10),
      textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
    );
    add(hud);
    add(FpsTextComponent(
      position: Vector2(12, 32),
      textRenderer:
          TextPaint(style: const TextStyle(color: _cyan, fontSize: 14, fontWeight: FontWeight.bold)),
    ));
    add(TextComponent(
      text: 'FLAME 엔진 테스트 (/lab)',
      position: Vector2(12, 54),
      textRenderer: TextPaint(style: TextStyle(color: _gold.withOpacity(0.7), fontSize: 11)),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    time += dt;
    spawnT -= dt;
    final interval = max(0.22, 1.0 - time * 0.012);
    if (spawnT <= 0) {
      spawnT = interval;
      _spawnEnemy();
      if (time > 30) _spawnEnemy(); // 후반 부하 테스트
      if (time > 60) _spawnEnemy();
    }
    hud.text =
        'Lv $level   처치 $kills   ${time.toStringAsFixed(0)}s   적 ${children.whereType<Enemy>().length}';
  }

  void _spawnEnemy() {
    final edge = rng.nextInt(4);
    final p = Vector2.zero();
    switch (edge) {
      case 0:
        p.setValues(rng.nextDouble() * size.x, -24);
        break;
      case 1:
        p.setValues(rng.nextDouble() * size.x, size.y + 24);
        break;
      case 2:
        p.setValues(-24, rng.nextDouble() * size.y);
        break;
      default:
        p.setValues(size.x + 24, rng.nextDouble() * size.y);
    }
    add(Enemy(p, 30 + time * 1.5));
  }

  void onKill(Vector2 at) {
    kills++;
    add(XpOrb(at.clone()));
    for (int i = 0; i < 6; i++) {
      add(Spark(at.clone(), Vector2(cos(i * 1.05) * 90, sin(i * 1.05) * 90)));
    }
  }

  void gainXp() {
    xp++;
    if (xp >= xpNeed) {
      xp = 0;
      level++;
      xpNeed += 3;
      player.onLevelUp(level);
    }
  }
}

// ─────────── 배경 그리드 ───────────
class GridBg extends Component with HasGameReference<AuhHeungLab> {
  final Paint _line = Paint()
    ..color = Colors.white.withOpacity(0.04)
    ..strokeWidth = 1;
  final Paint _glow = Paint()..color = _gold.withOpacity(0.05);

  @override
  int get priority => -10;

  @override
  void render(Canvas canvas) {
    final s = game.size;
    canvas.drawCircle(Offset(s.x / 2, s.y * 0.4), s.x * 0.6, _glow);
    const step = 48.0;
    for (double x = 0; x < s.x; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.y), _line);
    }
    for (double y = 0; y < s.y; y += step) {
      canvas.drawLine(Offset(0, y), Offset(s.x, y), _line);
    }
  }
}

// ─────────── 플레이어 (양→호랑이) ───────────
class Player extends PositionComponent with HasGameReference<AuhHeungLab>, CollisionCallbacks {
  double speed = 165;
  double fireT = 0;
  double fireInterval = 0.55;
  int tier = 0;
  double flash = 0;

  Player() : super(size: Vector2.all(34), anchor: Anchor.center, priority: 5);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox());
  }

  void onLevelUp(int level) {
    if (level >= 5 && tier < 1) tier = 1;
    if (level >= 12 && tier < 2) tier = 2;
    speed = 165 + tier * 12;
    fireInterval = (0.55 - level * 0.012).clamp(0.16, 0.55);
    flash = 1;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (flash > 0) flash = (flash - dt * 2).clamp(0, 1);
    final jd = game.joystick.relativeDelta;
    if (jd.length2 > 0.0001) {
      position += jd * speed * dt;
      position.clamp(Vector2.all(18), game.size - Vector2.all(18));
    }
    // 자동 발톱 공격 — 가장 가까운 적
    fireT -= dt;
    if (fireT <= 0) {
      Enemy? near;
      double best = 1e9;
      for (final e in game.children.whereType<Enemy>()) {
        final d = e.position.distanceToSquared(position);
        if (d < best) {
          best = d;
          near = e;
        }
      }
      if (near != null) {
        fireT = fireInterval;
        final dir = (near.position - position).normalized();
        game.add(Claw(position.clone(), dir));
        if (tier >= 2) game.add(Claw(position.clone(), Vector2(-dir.x, -dir.y)));
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final isTiger = tier >= 1;
    final body = isTiger ? _gold : const Color(0xFFEDE6D6);
    canvas.drawCircle(c, 20, Paint()..color = (isTiger ? _gold : _goldSoft).withOpacity(0.18));
    final ear = Paint()..color = body;
    canvas.drawCircle(c + const Offset(-9, -12), 5, ear);
    canvas.drawCircle(c + const Offset(9, -12), 5, ear);
    canvas.drawCircle(c, 14, Paint()..color = body);
    if (isTiger) {
      final stripe = Paint()
        ..color = const Color(0xFF1A1206)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c + const Offset(-8, -4), c + const Offset(-3, -2), stripe);
      canvas.drawLine(c + const Offset(8, -4), c + const Offset(3, -2), stripe);
      canvas.drawLine(c + const Offset(0, -9), c + const Offset(0, -4), stripe);
    }
    final eye = Paint()..color = isTiger ? const Color(0xFF1A1206) : _gold;
    canvas.drawCircle(c + const Offset(-5, -2), 2.2, eye);
    canvas.drawCircle(c + const Offset(5, -2), 2.2, eye);
    if (flash > 0) {
      canvas.drawCircle(c, 16, Paint()..color = Colors.white.withOpacity(0.5 * flash));
    }
  }

  @override
  void onCollisionStart(Set<Vector2> _, PositionComponent other) {
    if (_owner<Enemy>(other) != null) flash = 1;
  }
}

// ─────────── 적 ───────────
class Enemy extends PositionComponent with HasGameReference<AuhHeungLab>, CollisionCallbacks {
  final double spd;
  int hp = 2;
  double flash = 0;

  Enemy(Vector2 pos, this.spd)
      : super(position: pos, size: Vector2.all(26), anchor: Anchor.center, priority: 3);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (flash > 0) flash = (flash - dt * 4).clamp(0, 1);
    final dir = game.player.position - position;
    final len = dir.length;
    if (len > 0.01) position += dir / len * spd * dt;
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(c, 12, Paint()..color = const Color(0xFF12100E));
    canvas.drawCircle(
        c,
        12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = _red.withOpacity(0.95));
    canvas.drawCircle(c + const Offset(-4, -1), 2, Paint()..color = _red);
    canvas.drawCircle(c + const Offset(4, -1), 2, Paint()..color = _red);
    if (flash > 0) {
      canvas.drawCircle(c, 12, Paint()..color = Colors.white.withOpacity(0.7 * flash));
    }
  }

  void hit() {
    hp--;
    flash = 1;
    if (hp <= 0) {
      game.onKill(position);
      removeFromParent();
    }
  }
}

// ─────────── 발톱(투사체) ───────────
class Claw extends PositionComponent with HasGameReference<AuhHeungLab>, CollisionCallbacks {
  final Vector2 dir;
  double life = 1.6;
  static const double spd = 420;

  Claw(Vector2 pos, this.dir)
      : super(position: pos, size: Vector2.all(12), anchor: Anchor.center, priority: 4);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position += dir * spd * dt;
    life -= dt;
    if (life <= 0 ||
        position.x < -20 ||
        position.y < -20 ||
        position.x > game.size.x + 20 ||
        position.y > game.size.y + 20) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(c, 6, Paint()..color = _goldSoft.withOpacity(0.35));
    canvas.drawCircle(c, 3, Paint()..color = _goldSoft);
  }

  @override
  void onCollisionStart(Set<Vector2> _, PositionComponent other) {
    final e = _owner<Enemy>(other);
    if (e != null) {
      e.hit();
      removeFromParent();
    }
  }
}

// ─────────── 경험치 구슬 ───────────
class XpOrb extends PositionComponent with HasGameReference<AuhHeungLab>, CollisionCallbacks {
  XpOrb(Vector2 pos)
      : super(position: pos, size: Vector2.all(10), anchor: Anchor.center, priority: 2);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    final to = game.player.position - position;
    final d = to.length;
    if (d < 90 && d > 0.01) position += to / d * 220 * dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), 4, Paint()..color = _cyan);
  }

  @override
  void onCollisionStart(Set<Vector2> _, PositionComponent other) {
    if (_owner<Player>(other) != null) {
      game.gainXp();
      removeFromParent();
    }
  }
}

// ─────────── 처치 스파크 ───────────
class Spark extends PositionComponent {
  Vector2 vel;
  double life = 0.4;
  Spark(Vector2 pos, this.vel)
      : super(position: pos, size: Vector2.all(4), anchor: Anchor.center, priority: 6);

  @override
  void update(double dt) {
    super.update(dt);
    position += vel * dt;
    vel *= 0.92;
    life -= dt;
    if (life <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = (life / 0.4).clamp(0.0, 1.0);
    canvas.drawCircle(
        Offset(size.x / 2, size.y / 2), 2.2 * a + 0.5, Paint()..color = _gold.withOpacity(a));
  }
}
