// =============================================================================
//  프로젝트 어흥 : 야수의 생존 (SURVIVOR)
//  - 뱀서라이크. 드래그로 이동, 공격은 자동. 처치→마나구슬→레벨업→강화 3택.
//  - 선택에 따라 화면이 탄막지옥으로 — '성장이 눈에 보이는' 도파민.
//  - 에셋 0개. 모든 그래픽 CustomPainter. 고정 아레나(화면 안)에서 생존.
//  ⚠ 빌드 Flutter 3.24.5 — 투명도는 반드시 color.withOpacity(x). withValues 금지.
// =============================================================================
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() => runApp(const SurvivorApp());

class P {
  const P._();
  static const bg = Color(0xFF0E0B09);
  static const panel = Color(0xFF1A1410);
  static const gold = Color(0xFFE8A33D);
  static const goldSoft = Color(0xFFF3D89A);
  static const blood = Color(0xFFB7402E);
  static const green = Color(0xFF7FD08A);
  static const red = Color(0xFFE5604E);
  static const cyan = Color(0xFF5FD0E0);
  static const purple = Color(0xFFB07CE0);
  static const parch = Color(0xFFF0E6DC);
  static const muted = Color(0xFF9C8C7E);
  static const line = Color(0xFF3A2F28);
}

class SurvivorApp extends StatelessWidget {
  const SurvivorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '어흥 : 야수의 생존',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: P.bg, fontFamily: 'sans-serif', useMaterial3: false),
      home: const GameScreen(),
    );
  }
}

// =============================================================================
//  엔티티
// =============================================================================
enum EType { grunt, fast, tank, boss }

class Enemy {
  final int id;
  double x, y;
  double hp, maxHp;
  double speed, dmg, radius;
  EType type;
  double flash = 0; // 피격 섬광
  bool dead = false;
  Enemy(this.id, this.x, this.y, this.hp, this.maxHp, this.speed, this.dmg, this.radius, this.type);
}

class Bullet {
  double x, y, vx, vy, dmg, radius, life;
  int pierce;
  final Set<int> hitIds = {};
  bool dead = false;
  Bullet(this.x, this.y, this.vx, this.vy, this.dmg, this.radius, this.life, this.pierce);
}

class Orb {
  double x, y;
  final double value;
  bool dead = false;
  Orb(this.x, this.y, this.value);
}

class Particle {
  double x, y, vx, vy, life, maxLife, size;
  Color color;
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color) : maxLife = life;
}

class Pulse {
  double x, y, r, maxR, life, maxLife;
  Color color;
  Pulse(this.x, this.y, this.maxR, this.life, this.color)
      : r = 0,
        maxLife = life;
}

class Upgrade {
  final String icon, title, desc;
  final VoidCallback apply;
  const Upgrade(this.icon, this.title, this.desc, this.apply);
}

enum GPhase { title, playing, levelup, dead }

// =============================================================================
//  월드 / 게임 상태 + 업데이트 루프
// =============================================================================
class World {
  final Random rng = Random();
  GPhase phase = GPhase.title;

  double w = 0, h = 0; // 아레나 크기
  double time = 0; // 생존 시간(초)
  int kills = 0;

  // 플레이어
  double px = 0, py = 0;
  double hp = 100, baseMaxHp = 100;
  double baseSpeed = 132;
  double pr = 11; // 반지름
  int level = 1;
  double xp = 0, xpNext = 5;
  double orbitAngle = 0;
  double face = 0; // 바라보는 방향
  double contactCdView = 0; // 피격 점멸 표시용

  // 무기 레벨 (claw는 시작 보유 Lv1)
  int clawLv = 1, fangLv = 0, roarLv = 0;
  // 패시브 레벨
  int wildLv = 0, hideLv = 0, windLv = 0, hungerLv = 0, rageLv = 0;

  // 타이머
  double clawT = 0, roarT = 0, spawnT = 0, bossT = 90;

  // 엔티티
  final List<Enemy> enemies = [];
  final List<Bullet> bullets = [];
  final List<Orb> orbs = [];
  final List<Particle> parts = [];
  final List<Pulse> pulses = [];
  int _eid = 0;

  // 조이스틱
  bool jActive = false;
  double jbx = 0, jby = 0, jkx = 0, jky = 0, dirx = 0, diry = 0;

  // 레벨업 강화 선택지
  List<Upgrade> choices = [];

  // 기록
  double bestTime = 0;
  int bestKills = 0;

  // 햅틱 큐 (UI가 소비)
  bool _hapticHit = false, _hapticBig = false;

  World() {
    _loadRecords();
  }

  // ── 파생 스탯 ──
  double get maxHp => baseMaxHp + 25 * hideLv;
  double get speed => baseSpeed * (1 + 0.10 * windLv);
  double get pickupRange => 46 + 16.0 * hungerLv;
  double get dmgMult => 1 + 0.12 * wildLv;
  double get fireMult => 1 + 0.10 * rageLv;

  void startGame() {
    phase = GPhase.playing;
    time = 0;
    kills = 0;
    level = 1;
    xp = 0;
    xpNext = 5;
    clawLv = 1;
    fangLv = 0;
    roarLv = 0;
    wildLv = hideLv = windLv = hungerLv = rageLv = 0;
    clawT = 0;
    roarT = 0;
    spawnT = 0.6;
    bossT = 90;
    orbitAngle = 0;
    enemies.clear();
    bullets.clear();
    orbs.clear();
    parts.clear();
    pulses.clear();
    px = w / 2;
    py = h / 2;
    hp = maxHp;
    jActive = false;
    dirx = diry = 0;
  }

  // ── 입력 ──
  void joyStart(double x, double y) {
    jActive = true;
    jbx = x;
    jby = y;
    jkx = x;
    jky = y;
    dirx = diry = 0;
  }

  void joyMove(double x, double y) {
    if (!jActive) return;
    double dx = x - jbx, dy = y - jby;
    final len = sqrt(dx * dx + dy * dy);
    const maxR = 52.0;
    if (len > maxR) {
      dx = dx / len * maxR;
      dy = dy / len * maxR;
    }
    jkx = jbx + dx;
    jky = jby + dy;
    if (len > 6) {
      dirx = dx / max(len, 0.001);
      diry = dy / max(len, 0.001);
      if (len > maxR) {
        dirx = (x - jbx) / len;
        diry = (y - jby) / len;
      }
    } else {
      dirx = diry = 0;
    }
  }

  void joyEnd() {
    jActive = false;
    dirx = diry = 0;
  }

  // ── 메인 업데이트 ──
  void update(double dt) {
    if (phase != GPhase.playing) return;
    if (w <= 0 || h <= 0) return;
    if (dt > 0.05) dt = 0.05;
    time += dt;

    // 이동
    if (dirx != 0 || diry != 0) {
      px += dirx * speed * dt;
      py += diry * speed * dt;
      face = atan2(diry, dirx);
    }
    px = px.clamp(pr, w - pr);
    py = py.clamp(pr, h - pr);

    _spawn(dt);
    _fireWeapons(dt);
    _updateBullets(dt);
    _updateEnemies(dt);
    _collide(dt);
    _updateOrbs(dt);
    _updateFx(dt);

    // 사망
    if (hp <= 0) {
      hp = 0;
      _onDeath();
      return;
    }
    // 레벨업
    if (xp >= xpNext) {
      xp -= xpNext;
      level += 1;
      xpNext = (xpNext * 1.34 + 2).roundToDouble();
      _hapticBig = true;
      pulses.add(Pulse(px, py, 120, 0.5, P.gold));
      _openLevelUp();
    }
  }

  // ── 스폰 ──
  void _spawn(double dt) {
    bossT -= dt;
    if (bossT <= 0) {
      bossT = 90;
      _spawnBoss();
    }
    spawnT -= dt;
    if (spawnT > 0) return;
    final interval = max(0.32, 1.5 - time * 0.012).toDouble();
    spawnT = interval;
    if (enemies.length > 88) return;
    final count = 1 + (time ~/ 40);
    for (int i = 0; i < count; i++) {
      if (enemies.length > 88) break;
      _spawnOne();
    }
  }

  void _spawnOne() {
    // 화면 밖 가장자리
    double x, y;
    final side = rng.nextInt(4);
    if (side == 0) {
      x = rng.nextDouble() * w;
      y = -20;
    } else if (side == 1) {
      x = rng.nextDouble() * w;
      y = h + 20;
    } else if (side == 2) {
      x = -20;
      y = rng.nextDouble() * h;
    } else {
      x = w + 20;
      y = rng.nextDouble() * h;
    }
    // 타입 결정 (시간에 따라 흉포해짐)
    EType t = EType.grunt;
    final roll = rng.nextDouble();
    if (time > 60 && roll < 0.16) {
      t = EType.tank;
    } else if (time > 30 && roll < 0.42) {
      t = EType.fast;
    }
    final base = 12 + time * 0.85;
    Enemy e;
    if (t == EType.fast) {
      e = Enemy(_eid++, x, y, base * 0.7, base * 0.7, 78 + time * 0.22, 7 + time * 0.04, 9, t);
    } else if (t == EType.tank) {
      e = Enemy(_eid++, x, y, base * 3.4, base * 3.4, 34 + time * 0.08, 12 + time * 0.06, 18, t);
    } else {
      e = Enemy(_eid++, x, y, base, base, 50 + time * 0.16, 7 + time * 0.05, 11, t);
    }
    enemies.add(e);
  }

  void _spawnBoss() {
    final x = px + (rng.nextBool() ? 1 : -1) * w * 0.5;
    final y = py + (rng.nextBool() ? 1 : -1) * h * 0.4;
    final base = 240 + time * 6;
    enemies.add(Enemy(_eid++, x.clamp(0.0, w), y.clamp(0.0, h), base, base, 40, 22 + time * 0.08, 30, EType.boss));
    pulses.add(Pulse(px, py, 200, 0.6, P.blood));
    _hapticBig = true;
  }

  // ── 무기 발사 ──
  Enemy? _nearest() {
    Enemy? best;
    double bd = double.infinity;
    for (final e in enemies) {
      final d = (e.x - px) * (e.x - px) + (e.y - py) * (e.y - py);
      if (d < bd) {
        bd = d;
        best = e;
      }
    }
    return best;
  }

  void _fireWeapons(double dt) {
    // 발톱 폭풍 (투사체)
    clawT -= dt;
    if (clawT <= 0) {
      final cd = (1.0 * pow(0.9, clawLv - 1)) / fireMult;
      clawT = cd.toDouble();
      final target = _nearest();
      if (target != null && bullets.length < 200) {
        final n = 1 + (clawLv >= 2 ? 1 : 0) + (clawLv >= 4 ? 1 : 0) + (clawLv >= 6 ? 1 : 0);
        final dmg = (7 + clawLv * 4) * dmgMult;
        final pierce = clawLv >= 5 ? 1 : 0;
        final baseAng = atan2(target.y - py, target.x - px);
        for (int i = 0; i < n; i++) {
          final spread = (i - (n - 1) / 2) * 0.18;
          final a = baseAng + spread;
          bullets.add(Bullet(px, py, cos(a) * 340, sin(a) * 340, dmg, 6, 1.4, pierce));
        }
      }
    }
    // 포효 (충격파 — 즉발 광역)
    if (roarLv > 0) {
      roarT -= dt;
      if (roarT <= 0) {
        final cd = (2.6 * pow(0.93, roarLv - 1)) / fireMult;
        roarT = cd.toDouble();
        final radius = 70 + roarLv * 16.0;
        final dmg = (8 + roarLv * 6) * dmgMult;
        for (final e in enemies) {
          final d = sqrt((e.x - px) * (e.x - px) + (e.y - py) * (e.y - py));
          if (d <= radius + e.radius) {
            _hurt(e, dmg);
            // 살짝 밀어내기
            if (d > 0.1) {
              e.x += (e.x - px) / d * 14;
              e.y += (e.y - py) / d * 14;
            }
          }
        }
        pulses.add(Pulse(px, py, radius, 0.45, P.gold));
      }
    }
    // 회전 송곳니 (지속 접촉) — _collide에서 처리
    orbitAngle += dt * 2.6;
  }

  // ── 투사체 ──
  void _updateBullets(double dt) {
    for (final b in bullets) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.life -= dt;
      if (b.life <= 0 || b.x < -30 || b.x > w + 30 || b.y < -30 || b.y > h + 30) {
        b.dead = true;
      }
    }
    bullets.removeWhere((b) => b.dead);
  }

  // ── 적 ──
  void _updateEnemies(double dt) {
    for (final e in enemies) {
      final dx = px - e.x, dy = py - e.y;
      final d = sqrt(dx * dx + dy * dy);
      if (d > 0.1) {
        e.x += dx / d * e.speed * dt;
        e.y += dy / d * e.speed * dt;
      }
      if (e.flash > 0) e.flash -= dt * 4;
    }
  }

  // ── 충돌 ──
  void _collide(double dt) {
    // 투사체 vs 적
    for (final b in bullets) {
      if (b.dead) continue;
      for (final e in enemies) {
        if (e.dead || b.hitIds.contains(e.id)) continue;
        final rr = (b.radius + e.radius);
        if ((b.x - e.x) * (b.x - e.x) + (b.y - e.y) * (b.y - e.y) <= rr * rr) {
          _hurt(e, b.dmg);
          b.hitIds.add(e.id);
          if (b.pierce <= 0) {
            b.dead = true;
            break;
          } else {
            b.pierce -= 1;
          }
        }
      }
    }
    bullets.removeWhere((b) => b.dead);

    // 회전 송곳니 vs 적 (지속 DPS)
    if (fangLv > 0) {
      final cnt = fangLv;
      final orad = 60 + fangLv * 4.0;
      final fdps = (22 + fangLv * 14) * dmgMult;
      final fr = 13.0;
      for (int i = 0; i < cnt; i++) {
        final a = orbitAngle + i * 6.2831853 / cnt;
        final fx = px + cos(a) * orad;
        final fy = py + sin(a) * orad;
        for (final e in enemies) {
          if (e.dead) continue;
          final rr = fr + e.radius;
          if ((fx - e.x) * (fx - e.x) + (fy - e.y) * (fy - e.y) <= rr * rr) {
            _hurt(e, fdps * dt);
          }
        }
      }
    }

    // 적 vs 플레이어 (접촉 지속 데미지)
    contactCdView = max(0.0, contactCdView - dt);
    for (final e in enemies) {
      final rr = e.radius + pr;
      if ((e.x - px) * (e.x - px) + (e.y - py) * (e.y - py) <= rr * rr) {
        hp -= e.dmg * dt;
        contactCdView = 0.12;
        _hapticHit = true;
      }
    }

    // 죽은 적 처리 → 구슬/파티클
    for (final e in enemies) {
      if (e.hp <= 0 && !e.dead) {
        e.dead = true;
        kills += 1;
        final drops = e.type == EType.boss ? 14 : (e.type == EType.tank ? 3 : 1);
        for (int i = 0; i < drops; i++) {
          orbs.add(Orb(e.x + (rng.nextDouble() - 0.5) * 24, e.y + (rng.nextDouble() - 0.5) * 24,
              e.type == EType.boss ? 4.0 : 1.0));
        }
        final col = e.type == EType.fast ? P.purple : (e.type == EType.tank ? P.blood : P.muted);
        for (int i = 0; i < (e.type == EType.boss ? 22 : 7); i++) {
          final a = rng.nextDouble() * 6.2831853;
          final sp = 40 + rng.nextDouble() * 120;
          parts.add(Particle(e.x, e.y, cos(a) * sp, sin(a) * sp, 0.4 + rng.nextDouble() * 0.3,
              2 + rng.nextDouble() * 3, col));
        }
      }
    }
    enemies.removeWhere((e) => e.dead);
  }

  void _hurt(Enemy e, double dmg) {
    e.hp -= dmg;
    e.flash = 1;
  }

  // ── 구슬 ──
  void _updateOrbs(double dt) {
    final pr2 = pickupRange * pickupRange;
    for (final o in orbs) {
      final dx = px - o.x, dy = py - o.y;
      final d2 = dx * dx + dy * dy;
      if (d2 < pr2) {
        final d = sqrt(d2);
        final pull = 120 + (pickupRange - d) * 4;
        if (d > 0.1) {
          o.x += dx / d * pull * dt;
          o.y += dy / d * pull * dt;
        }
        if (d < 16) {
          xp += o.value;
          o.dead = true;
        }
      }
    }
    orbs.removeWhere((o) => o.dead);
  }

  void _updateFx(double dt) {
    for (final p in parts) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.92;
      p.vy *= 0.92;
      p.life -= dt;
    }
    parts.removeWhere((p) => p.life <= 0);
    for (final p in pulses) {
      p.life -= dt;
      p.r = p.maxR * (1 - (p.life / p.maxLife));
    }
    pulses.removeWhere((p) => p.life <= 0);
  }

  // ── 레벨업 강화 ──
  void _openLevelUp() {
    phase = GPhase.levelup;
    final pool = <Upgrade>[];
    if (clawLv < 8) {
      pool.add(Upgrade('🪝', '발톱 폭풍', clawLv == 0 ? '발톱 투사체를 자동으로 날린다' : '투사체 강화 (Lv ${clawLv + 1})',
          () => clawLv++));
    }
    if (fangLv < 6) {
      pool.add(Upgrade('🦷', '회전 송곳니', fangLv == 0 ? '몸 주위를 도는 송곳니 소환' : '송곳니 추가·강화 (Lv ${fangLv + 1})',
          () => fangLv++));
    }
    if (roarLv < 7) {
      pool.add(Upgrade('💢', '포효', roarLv == 0 ? '주기적으로 주변을 휩쓰는 충격파' : '포효 범위·위력 강화 (Lv ${roarLv + 1})',
          () => roarLv++));
    }
    pool.add(Upgrade('🐅', '야성', '모든 공격력 +12% (Lv ${wildLv + 1})', () => wildLv++));
    pool.add(Upgrade('🛡', '가죽', '최대 체력 +25, 즉시 25 회복', () {
      hideLv++;
      hp = min(hp + 25, maxHp);
    }));
    pool.add(Upgrade('🌬', '바람', '이동 속도 +10% (Lv ${windLv + 1})', () => windLv++));
    pool.add(Upgrade('👅', '굶주림', '구슬 수집 범위 +16 (Lv ${hungerLv + 1})', () => hungerLv++));
    pool.add(Upgrade('🔥', '분노', '공격 속도 +10% (Lv ${rageLv + 1})', () => rageLv++));
    pool.shuffle(rng);
    choices = pool.take(3).toList();
  }

  void pick(Upgrade u) {
    u.apply();
    choices = [];
    phase = GPhase.playing;
  }

  void _onDeath() {
    phase = GPhase.dead;
    _hapticBig = true;
    if (time > bestTime) bestTime = time;
    if (kills > bestKills) bestKills = kills;
    _saveRecords();
  }

  // ── 햅틱 큐 소비 ──
  void consumeHaptics() {
    try {
      if (_hapticBig) {
        HapticFeedback.heavyImpact();
      } else if (_hapticHit) {
        HapticFeedback.selectionClick();
      }
    } catch (_) {}
    _hapticBig = false;
    _hapticHit = false;
  }

  // ── 기록 저장 ──
  void _loadRecords() {
    try {
      final raw = html.window.localStorage['surv_rec'];
      if (raw == null) return;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      bestTime = (j['bt'] as num?)?.toDouble() ?? 0;
      bestKills = j['bk'] as int? ?? 0;
    } catch (_) {}
  }

  void _saveRecords() {
    try {
      html.window.localStorage['surv_rec'] = jsonEncode({'bt': bestTime, 'bk': bestKills});
    } catch (_) {}
  }

  static String mmss(double t) {
    final s = t.floor();
    final m = s ~/ 60;
    final ss = s % 60;
    return '${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
//  게임 화면 (틱 루프 + 입력 + HUD/오버레이)
// =============================================================================
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  final World world = World();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    world.update(dt);
    world.consumeHaptics();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, cons) {
          world.w = cons.maxWidth;
          world.h = cons.maxHeight;
          return Stack(children: [
            // 게임 레이어 + 입력
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => world.joyStart(d.localPosition.dx, d.localPosition.dy),
                onPanUpdate: (d) => world.joyMove(d.localPosition.dx, d.localPosition.dy),
                onPanEnd: (_) => world.joyEnd(),
                onPanCancel: () => world.joyEnd(),
                child: RepaintBoundary(
                  child: CustomPaint(size: Size.infinite, painter: WorldPainter(world)),
                ),
              ),
            ),
            if (world.phase == GPhase.playing || world.phase == GPhase.levelup) _hud(),
            if (world.phase == GPhase.title) _title(),
            if (world.phase == GPhase.levelup) _levelUp(),
            if (world.phase == GPhase.dead) _death(),
          ]);
        }),
      ),
    );
  }

  // ── HUD ──
  Widget _hud() {
    final hpFrac = (world.hp / world.maxHp).clamp(0.0, 1.0);
    final xpFrac = (world.xp / world.xpNext).clamp(0.0, 1.0);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Column(children: [
            Row(children: [
              _tag('🕒 ${World.mmss(world.time)}'),
              const SizedBox(width: 8),
              _tag('Lv ${world.level}', color: P.gold),
              const Spacer(),
              _tag('☠ ${world.kills}', color: P.red),
            ]),
            const SizedBox(height: 8),
            // 체력
            _bar(hpFrac, P.red, height: 11,
                label: '❤ ${world.hp.ceil()} / ${world.maxHp.round()}'),
            const SizedBox(height: 5),
            // 경험치
            _bar(xpFrac, P.cyan, height: 6),
          ]),
        ),
      ),
    );
  }

  Widget _tag(String t, {Color color = P.parch}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(t,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _bar(double frac, Color color, {double height = 8, String? label}) {
    return Stack(alignment: Alignment.center, children: [
      Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black.withOpacity(0.3)),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac == 0 ? 0.001 : frac,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 5)],
            ),
          ),
        ),
      ),
      if (label != null)
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                height: 1.0)),
    ]);
  }

  // ── 타이틀 ──
  Widget _title() {
    return Container(
      color: Colors.black.withOpacity(0.55),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🐯', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 8),
        const Text('어흥 : 야수의 생존',
            style: TextStyle(
                color: P.gold, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 14),
        const Text('드래그로 이동 · 공격은 자동\n쏟아지는 의회의 졸개들 속에서 버텨라',
            textAlign: TextAlign.center,
            style: TextStyle(color: P.parch, fontSize: 14, height: 1.7)),
        const SizedBox(height: 10),
        if (world.bestTime > 0)
          Text('최고 기록 ${World.mmss(world.bestTime)} · ${world.bestKills}킬',
              style: const TextStyle(color: P.muted, fontSize: 13)),
        const SizedBox(height: 26),
        _bigBtn('⚔  생존 시작', P.gold, () => setState(() => world.startGame())),
      ]),
    );
  }

  // ── 레벨업 강화 3택 ──
  Widget _levelUp() {
    return Container(
      color: Colors.black.withOpacity(0.72),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('⚡ LEVEL UP',
            style: TextStyle(
                color: P.gold, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 3)),
        const SizedBox(height: 6),
        Text('Lv ${world.level} — 성장의 길을 고르십시오',
            style: const TextStyle(color: P.muted, fontSize: 13)),
        const SizedBox(height: 18),
        ...world.choices.map((u) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _upgradeCard(u),
            )),
      ]),
    );
  }

  Widget _upgradeCard(Upgrade u) {
    return Material(
      color: P.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => world.pick(u)),
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: P.gold.withOpacity(0.7), width: 1.5),
          ),
          child: Row(children: [
            Text(u.icon, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.title,
                    style: const TextStyle(
                        color: P.goldSoft, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(u.desc, style: const TextStyle(color: P.parch, fontSize: 12.5, height: 1.3)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── 사망 ──
  Widget _death() {
    return Container(
      color: Colors.black.withOpacity(0.78),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('☠️', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 10),
        const Text('쓰러지다',
            style: TextStyle(
                color: P.red, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: P.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: P.line),
          ),
          child: Column(children: [
            Text('생존 ${World.mmss(world.time)}',
                style: const TextStyle(color: P.parch, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Lv ${world.level} · ${world.kills}킬',
                style: const TextStyle(color: P.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Text('최고 ${World.mmss(world.bestTime)} · ${world.bestKills}킬',
                style: const TextStyle(color: P.gold, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 24),
        _bigBtn('🔥  다시 일어선다', P.blood, () => setState(() => world.startGame()), dark: false),
      ]),
    );
  }

  Widget _bigBtn(String t, Color c, VoidCallback onTap, {bool dark = true}) => Material(
        color: c,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
            child: Text(t,
                style: TextStyle(
                    color: dark ? Colors.black : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      );
}

// =============================================================================
//  월드 페인터 — 모든 그래픽을 코드로
// =============================================================================
class WorldPainter extends CustomPainter {
  final World w;
  WorldPainter(this.w);

  @override
  void paint(Canvas canvas, Size size) {
    // 배경
    final bg = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF1B140D), Color(0xFF0A0807)],
        radius: 0.95,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    _grid(canvas, size);

    if (w.phase == GPhase.title) return;

    // 마나 구슬
    final orbP = Paint();
    for (final o in w.orbs) {
      orbP.color = P.cyan.withOpacity(0.9);
      canvas.drawCircle(Offset(o.x, o.y), 3.2, orbP);
      orbP.color = P.cyan.withOpacity(0.25);
      canvas.drawCircle(Offset(o.x, o.y), 6.5, orbP);
    }

    // 포효/펄스
    for (final p in w.pulses) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 4 * a
        ..color = p.color.withOpacity(0.5 * a);
      canvas.drawCircle(Offset(p.x, p.y), p.r, ring);
    }

    // 적
    for (final e in w.enemies) {
      _enemy(canvas, e);
    }

    // 투사체 (발톱)
    final bp = Paint()..color = P.goldSoft;
    for (final b in w.bullets) {
      canvas.drawCircle(Offset(b.x, b.y), b.radius * 0.6, bp);
      final glow = Paint()..color = P.gold.withOpacity(0.3);
      canvas.drawCircle(Offset(b.x, b.y), b.radius, glow);
    }

    // 회전 송곳니
    if (w.fangLv > 0) {
      final orad = 60 + w.fangLv * 4.0;
      final fp = Paint()..color = Colors.white;
      for (int i = 0; i < w.fangLv; i++) {
        final a = w.orbitAngle + i * 6.2831853 / w.fangLv;
        final fx = w.px + cos(a) * orad;
        final fy = w.py + sin(a) * orad;
        canvas.drawCircle(Offset(fx, fy), 6, fp);
        canvas.drawCircle(Offset(fx, fy), 11, Paint()..color = Colors.white.withOpacity(0.22));
      }
    }

    // 파티클
    for (final pt in w.parts) {
      final a = (pt.life / pt.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(pt.x, pt.y), pt.size * a, Paint()..color = pt.color.withOpacity(a));
    }

    // 플레이어 (백호)
    _player(canvas);

    // 조이스틱
    if (w.jActive) {
      final base = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.18);
      canvas.drawCircle(Offset(w.jbx, w.jby), 52, base);
      canvas.drawCircle(Offset(w.jkx, w.jky), 22, Paint()..color = Colors.white.withOpacity(0.28));
    }
  }

  void _grid(Canvas canvas, Size size) {
    final g = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 1;
    const step = 46.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), g);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
  }

  void _enemy(Canvas canvas, Enemy e) {
    Color base;
    switch (e.type) {
      case EType.fast:
        base = P.purple;
        break;
      case EType.tank:
        base = P.blood;
        break;
      case EType.boss:
        base = const Color(0xFFE03020);
        break;
      case EType.grunt:
        base = const Color(0xFF6B5E54);
        break;
    }
    // 그림자 본체
    canvas.drawCircle(Offset(e.x, e.y), e.radius,
        Paint()..color = const Color(0xFF0C0A08).withOpacity(0.9));
    canvas.drawCircle(Offset(e.x, e.y), e.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = base);
    // 붉은 눈
    final eye = Paint()..color = base;
    canvas.drawCircle(Offset(e.x - e.radius * 0.32, e.y - e.radius * 0.1), e.radius * 0.16, eye);
    canvas.drawCircle(Offset(e.x + e.radius * 0.32, e.y - e.radius * 0.1), e.radius * 0.16, eye);
    // 피격 섬광
    if (e.flash > 0) {
      canvas.drawCircle(Offset(e.x, e.y), e.radius,
          Paint()..color = Colors.white.withOpacity(0.55 * e.flash.clamp(0.0, 1.0)));
    }
    // 보스 체력 링
    if (e.type == EType.boss) {
      final frac = (e.hp / e.maxHp).clamp(0.0, 1.0);
      canvas.drawArc(
          Rect.fromCircle(center: Offset(e.x, e.y), radius: e.radius + 5),
          -1.5708,
          6.2831853 * frac,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = P.red);
    }
  }

  void _player(Canvas canvas) {
    final hurt = w.contactCdView > 0;
    final body = Paint()
      ..color = hurt ? P.red : P.gold;
    // 안광
    canvas.drawCircle(Offset(w.px, w.py), w.pr * 2.2,
        Paint()..color = P.gold.withOpacity(0.18));
    // 귀
    final ear = Path()
      ..moveTo(w.px - w.pr * 0.9, w.py - w.pr * 0.5)
      ..lineTo(w.px - w.pr * 0.4, w.py - w.pr * 1.25)
      ..lineTo(w.px - w.pr * 0.1, w.py - w.pr * 0.6)
      ..close()
      ..moveTo(w.px + w.pr * 0.9, w.py - w.pr * 0.5)
      ..lineTo(w.px + w.pr * 0.4, w.py - w.pr * 1.25)
      ..lineTo(w.px + w.pr * 0.1, w.py - w.pr * 0.6)
      ..close();
    canvas.drawPath(ear, body);
    // 얼굴
    canvas.drawCircle(Offset(w.px, w.py), w.pr, body);
    // 눈
    final eye = Paint()..color = const Color(0xFF1A1208);
    canvas.drawCircle(Offset(w.px - w.pr * 0.38, w.py - w.pr * 0.05), w.pr * 0.18, eye);
    canvas.drawCircle(Offset(w.px + w.pr * 0.38, w.py - w.pr * 0.05), w.pr * 0.18, eye);
    // 코
    canvas.drawCircle(Offset(w.px, w.py + w.pr * 0.35), w.pr * 0.13, eye);
  }

  @override
  bool shouldRepaint(covariant WorldPainter old) => true;
}
