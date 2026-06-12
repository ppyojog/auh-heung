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
import 'dart:typed_data';
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

class FloatText {
  double x, y, life, maxLife, size;
  final String text;
  final Color color;
  FloatText(this.x, this.y, this.text, this.color, this.size)
      : life = 0.7,
        maxLife = 0.7;
}

class LineFx {
  final double x1, y1, x2, y2;
  final Color color;
  double life;
  final double maxLife;
  LineFx(this.x1, this.y1, this.x2, this.y2, this.color)
      : life = 0.16,
        maxLife = 0.16;
}

class Upgrade {
  final String icon, title, desc;
  final VoidCallback apply;
  const Upgrade(this.icon, this.title, this.desc, this.apply);
}

// 충신 '타이니' — 플레이어를 과장되게 떠받드는 herald (USP: 양→호랑이 뽕).
//  전부 텍스트(무음) → 회사에서 몰래 해도 소리 없이 뽕이 온다.
class Tiny {
  const Tiny._();
  static const greet = [
    '대장님, 오늘도 의회 놈들의 간담을 서늘하게 해주시죠. 제가 곁을 지킵니다.',
    '크흐… 사냥의 시간입니다. 저 타이니, 대장님의 마지막 송곳니가 함께합니다.',
  ];
  static const level = [
    '또 강해지셨습니까 대장님?! 하늘마저 대장님 편입니다!',
    '이 힘… 대륙이 대장님을 중심으로 돕니다!',
    '크하핫! 누가 감히 대장님을 양이라 했습니까!',
    '한 꺼풀 벗을 때마다 더 사나워지시는군요. 역시 제 주인!',
  ];
  static const boss = [
    '보셨습니까! 의회의 거수가 대장님 발톱에 찢겼습니다!',
    '저 거대한 놈도 대장님 앞에선 한낱 먹잇감이었군요!',
  ];
  static const ult = [
    '크하핫—! 대륙이 대장님의 포효 앞에 무릎 꿇습니다!!',
    '어흥!! 이것이 진정한 맹수의 울음입니다, 대장님!',
  ];
  static const low = [
    '대장님 정도면 이건 일부러 봐주시는 거죠…? 그렇죠?!',
    '피 좀 보이는 게 대숩니까! 대장님은 더 사나워질 뿐입니다!',
  ];
  static const streak = [
    '멈추질 않으십니다! 놈들이 줄지어 쓰러집니다!',
    '대장님 지나간 자리엔 시체만 쌓입니다!',
  ];
}

// 캐릭터 — 시작 무기·스탯이 달라 플레이 결이 바뀐다(리플레이성)
class Character {
  final String id, name, icon, desc, startWeapon;
  final Color color;
  final double dmg, hp, speed;
  const Character(this.id, this.name, this.icon, this.desc, this.color, this.startWeapon,
      {this.dmg = 1, this.hp = 1, this.speed = 1});
}

const List<Character> kChars = [
  Character('white', '백호 부족장', '🐯', '균형의 맹수. 발톱 폭풍으로 시작.', P.gold, 'claw'),
  Character('black', '그림자 흑표', '🐆', '유리대포. 공격력↑ 체력↓. 회전 송곳니로 시작.', P.purple, 'fang',
      dmg: 1.3, hp: 0.7, speed: 1.12),
  Character('iron', '무쇠뿔 들소', '🐃', '육중한 탱크. 체력↑ 느림. 포효로 시작.', P.cyan, 'roar',
      dmg: 0.9, hp: 1.6, speed: 0.82),
];

// =============================================================================
//  사운드 — 에셋 0. Dart에서 PCM 합성 → WAV → data URI → AudioElement 재생.
//  (Web Audio API 메서드명 리스크 회피, 전부 안정적인 표준 API)
// =============================================================================
class Sfx {
  final Map<String, html.AudioElement> _el = {};
  final Map<String, int> _last = {};
  final Random _r = Random(99);
  bool muted = false;
  bool _built = false;

  void init() {
    if (_built) return;
    _built = true;
    try {
      _el['shoot'] = _mk(_mkWrap(_one(freq: 680, to: 430, dur: 0.09, type: 'square', vol: 0.14, dec: 0.07)));
      _el['hit'] = _mk(_mkWrap(_one(freq: 220, to: 110, dur: 0.07, type: 'square', vol: 0.16, noise: 0.5, dec: 0.06)));
      _el['pick'] = _mk(_mkWrap(_one(freq: 880, to: 1330, dur: 0.06, type: 'sine', vol: 0.11, dec: 0.05)));
      _el['level'] = _mk(_arp([523.25, 659.25, 783.99, 1046.5], 0.085, vol: 0.2));
      _el['roar'] = _mk(_mkWrap(_one(freq: 150, to: 60, dur: 0.4, type: 'saw', vol: 0.28, noise: 0.25, dec: 0.36)));
      _el['boss'] = _mk(_mkWrap(_one(freq: 84, to: 68, dur: 0.7, type: 'saw', vol: 0.32, dec: 0.6, trem: 7)));
      _el['death'] = _mk(_mkWrap(_one(freq: 320, to: 52, dur: 0.8, type: 'saw', vol: 0.3, dec: 0.75)));
    } catch (_) {}
  }

  html.AudioElement _mk(Uint8List wav) {
    final uri = 'data:audio/wav;base64,${base64Encode(wav)}';
    return html.AudioElement()
      ..src = uri
      ..preload = 'auto';
  }

  void play(String name, {int gapMs = 0}) {
    if (muted) return;
    final a = _el[name];
    if (a == null) return;
    if (gapMs > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((_last[name] ?? 0) + gapMs > now) return;
      _last[name] = now;
    }
    try {
      a.currentTime = 0;
      a.play();
    } catch (_) {}
  }

  // 단일 톤(스윕·노이즈·트레몰로·감쇠 포함) 샘플
  List<double> _one({
    required double freq,
    double? to,
    required double dur,
    String type = 'sine',
    double vol = 0.3,
    double dec = 0.0,
    double noise = 0.0,
    double trem = 0.0,
    int rate = 22050,
  }) {
    final n = (dur * rate).round();
    final s = List<double>.filled(n, 0.0);
    const atk = 0.008;
    final d = dec <= 0 ? dur : dec;
    for (int i = 0; i < n; i++) {
      final t = i / rate;
      final p = n <= 1 ? 0.0 : i / n;
      final f = to == null ? freq : freq + (to - freq) * p;
      final ph = 2 * pi * f * t;
      double v;
      if (type == 'square') {
        v = sin(ph) >= 0 ? 1.0 : -1.0;
      } else if (type == 'saw') {
        v = 2 * ((f * t) % 1.0) - 1.0;
      } else {
        v = sin(ph);
      }
      if (noise > 0) v = v * (1 - noise) + (_r.nextDouble() * 2 - 1) * noise;
      double env;
      if (t < atk) {
        env = t / atk;
      } else {
        env = (1 - (t - atk) / d).clamp(0.0, 1.0);
      }
      if (trem > 0) env *= 0.6 + 0.4 * sin(2 * pi * trem * t);
      s[i] = (v * env * vol).clamp(-1.0, 1.0);
    }
    return s;
  }

  Uint8List _arp(List<double> freqs, double each, {double vol = 0.22}) {
    final all = <double>[];
    for (final f in freqs) {
      all.addAll(_one(freq: f, dur: each, type: 'square', vol: vol, dec: each * 0.9));
    }
    return _wav(all, 22050);
  }

  Uint8List _mkWrap(List<double> s) => _wav(s, 22050);

  Uint8List _wav(List<double> s, int rate) {
    final n = s.length;
    final b = ByteData(44 + n * 2);
    void tag(int off, String t) {
      for (int i = 0; i < t.length; i++) {
        b.setUint8(off + i, t.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    b.setUint32(4, 36 + n * 2, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    b.setUint32(40, n * 2, Endian.little);
    for (int i = 0; i < n; i++) {
      b.setInt16(44 + i * 2, (s[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }
}

enum GPhase { title, playing, levelup, choice, dead, shop, menu, achieve, skins }

// 영구 강화(메타 진행) — 죽어도 남는 '송곳니'로 구매. 죽음이 헛되지 않게.
class MetaUp {
  final String id, icon, name, desc;
  final int baseCost, maxLv;
  final double growth;
  const MetaUp(this.id, this.icon, this.name, this.desc, this.baseCost, this.maxLv,
      [this.growth = 1.55]);
}

const List<MetaUp> kMeta = [
  MetaUp('atk', '💪', '맹수의 발톱', '시작 공격력 +5%', 30, 10),
  MetaUp('hp', '❤', '두꺼운 가죽', '시작 체력 +15', 25, 10),
  MetaUp('spd', '🌬', '바람의 다리', '시작 이동속도 +4%', 30, 6),
  MetaUp('pick', '🧲', '굶주린 코', '수집 범위 +8', 25, 6),
  MetaUp('gain', '🦷', '전리품 사냥꾼', '송곳니 획득 +12%', 40, 8),
];

// 업적 — 달성 시 송곳니 보상 + 영구 기록(리텐션·목표)
class Ach {
  final String id, icon, name, desc;
  final int reward;
  const Ach(this.id, this.icon, this.name, this.desc, this.reward);
}

const List<Ach> kAch = [
  Ach('kill10', '🩸', '첫 사냥', '적 10마리 처치', 10),
  Ach('surv60', '⏳', '한 숨 돌리다', '1분 생존', 15),
  Ach('lv10', '⭐', '성장하는 맹수', '레벨 10 도달', 20),
  Ach('stage5', '🌊', '거센 파도', '스테이지 5 도달', 25),
  Ach('kill100', '💀', '학살자', '한 판 100킬', 25),
  Ach('boss1', '👹', '거수 사냥꾼', '보스 처치', 30),
  Ach('dev200', '🍖', '대식가', '한 판 200 포식', 30),
  Ach('surv180', '🏆', '살아있는 전설', '3분 생존', 40),
];

// 코스메틱 스킨 — 호랑이 색 변경(P2W 없음, 윤리적 수익화). 송곳니로 해금.
class Skin {
  final String id, name, icon;
  final Color color;
  final int cost;
  const Skin(this.id, this.name, this.icon, this.color, this.cost);
}

const List<Skin> kSkins = [
  Skin('default', '기본 (캐릭터색)', '🐯', Color(0x00000000), 0),
  Skin('snow', '눈호랑이', '❄', Color(0xFFBFE8F5), 60),
  Skin('shadow', '그림자 표범', '🌑', Color(0xFFB07CE0), 80),
  Skin('ember', '잿불 맹수', '🔥', Color(0xFFE8702E), 80),
  Skin('jade', '비취 야수', '🍃', Color(0xFF7FD08A), 110),
  Skin('royal', '황금 폭군', '👑', Color(0xFFFFD54F), 160),
];

// 타이니 선택 대화 — 난이도를 가르는 분기 (선택권은 주되 욕망으로 망할 수 있는 구조)
class TinyChoice {
  final String prompt, leftLabel, leftSub, rightLabel, rightSub;
  final void Function() onLeft;
  final void Function() onRight;
  TinyChoice(this.prompt, this.leftLabel, this.leftSub, this.onLeft, this.rightLabel,
      this.rightSub, this.onRight);
}

// =============================================================================
//  월드 / 게임 상태 + 업데이트 루프
// =============================================================================
class World {
  final Random rng = Random();
  final Sfx sfx = Sfx();
  GPhase phase = GPhase.title;

  double w = 0, h = 0; // 아레나 크기
  double time = 0; // 생존 시간(초)
  int kills = 0;
  int _mileShown = 0; // 생존 마일스톤 연출 카운터

  // 플레이어
  double px = 0, py = 0;
  double hp = 120, baseMaxHp = 120;
  double baseSpeed = 156;
  double pr = 11; // 반지름
  // 광기(어흥!) 궁극기 — 처치로 차오르고, 해방 시 화면 대포효 + 광폭화
  double rage = 0, rageMax = 75, berserkT = 0;
  // 펫 타이니 — 플레이어를 졸졸 따라다니며 표정으로 반응
  double petX = 0, petY = 0, petHappyT = 0;
  // 포식(Devour) — 삼킬수록 회복 + 호랑이가 점점 커짐 (양→호랑이 USP)
  int devour = 0;
  double get growScale => (0.9 + devour * 0.005).clamp(0.9, 1.6);
  // 업적
  final Set<String> achieved = {};
  final List<String> pendingAch = []; // 이번 사망에서 새로 달성한 것
  int runBoss = 0; // 이번 런 보스 처치 수
  // 코스메틱 스킨
  final Set<String> ownedSkins = {'default'};
  String skin = 'default';
  // 데일리 보너스
  String lastDaily = '';
  bool dailyJustClaimed = false;

  Color get skinColor {
    if (skin == 'default') return kChars[charIndex.clamp(0, kChars.length - 1)].color;
    final s = kSkins.firstWhere((e) => e.id == skin, orElse: () => kSkins.first);
    return s.id == 'default' ? kChars[charIndex.clamp(0, kChars.length - 1)].color : s.color;
  }

  bool buySkin(String id) {
    final s = kSkins.firstWhere((e) => e.id == id);
    if (ownedSkins.contains(id)) return false;
    if (fangs < s.cost) return false;
    fangs -= s.cost;
    ownedSkins.add(id);
    skin = id;
    _saveMeta();
    return true;
  }

  void selectSkin(String id) {
    if (!ownedSkins.contains(id)) return;
    skin = id;
    _saveMeta();
  }
  // 충신 herald (텍스트 대사 + 표정으로 톤 전달)
  String heraldLine = '';
  String heraldFace = '🐯';
  double heraldT = 0, _heraldCd = 0, _lowCd = 0;
  GPhase shopReturn = GPhase.title; // 상점에서 돌아갈 화면
  int _streakKillMark = 0;
  // 동적 난이도 (타이니 선택으로 변동) — 높을수록 적 강함 + XP·광기 획득 ↑(빠른 성장)
  double diff = 1.0;
  TinyChoice? tinyChoice;
  double _choiceCd = 14, _advT = 48;
  int level = 1;
  double xp = 0, xpNext = 5;
  double orbitAngle = 0;
  double face = 0; // 바라보는 방향
  double contactCdView = 0; // 피격 점멸 표시용

  // 무기 레벨 (claw는 시작 보유 Lv1)
  int clawLv = 1, fangLv = 0, roarLv = 0, boltLv = 0, spikeLv = 0;
  // 무기 진화 (최대 레벨 + 시너지 패시브 → 초월 무기)
  bool clawEvo = false, fangEvo = false, roarEvo = false;
  // 패시브 레벨
  int wildLv = 0, hideLv = 0, windLv = 0, hungerLv = 0, rageLv = 0;
  // 선택 캐릭터 + 시작 배수
  int charIndex = 0;
  double charDmg = 1, charHp = 1, charSpeed = 1;

  // 타이머
  double clawT = 0, roarT = 0, spawnT = 0, bossT = 90, boltT = 0, spikeT = 0;

  // 엔티티
  final List<Enemy> enemies = [];
  final List<Bullet> bullets = [];
  final List<Orb> orbs = [];
  final List<Particle> parts = [];
  final List<Pulse> pulses = [];
  final List<FloatText> floats = []; // 데미지 숫자 등
  final List<LineFx> lines = []; // 벼락 등 선형 이펙트
  double shake = 0; // 화면 흔들림 강도
  int _eid = 0;

  void _shakeAdd(double v) {
    if (v > shake) shake = v;
  }

  void _float(double x, double y, String t, Color c, double size) {
    if (floats.length > 46) floats.removeAt(0);
    floats.add(FloatText(x, y, t, c, size));
  }

  String _pick(List<String> p) => p[rng.nextInt(p.length)];

  // 충신 대사 출력 (force=false면 잡담 도배 방지 쿨다운). face=표정으로 톤 전달.
  void _say(String line, {double dur = 3.2, bool force = false, String face = '🐯'}) {
    if (!force && _heraldCd > 0) return;
    heraldLine = line;
    heraldFace = face;
    heraldT = dur;
    _heraldCd = 0.8;
  }

  int get stage => 1 + (time ~/ 45).toInt(); // 45초마다 +1, 계속 증가 → 성장/escalation 체감

  void openMenu() {
    if (phase == GPhase.playing) phase = GPhase.menu;
  }

  void resume() {
    if (phase == GPhase.menu) phase = GPhase.playing;
  }

  void giveUp() {
    if (phase == GPhase.menu || phase == GPhase.playing) _onDeath();
  }

  // [치트] 내부 테스트 — 즉시 +10 레벨 + 자동 강화 10회
  void cheatLevel10() {
    if (phase != GPhase.menu && phase != GPhase.playing) return;
    for (int i = 0; i < 10; i++) {
      level += 1;
      _autoUpgrade();
    }
    hp = maxHp;
    rage = rageMax;
    phase = GPhase.playing;
    _say('🐞 치트! 대장님이 순식간에 +10 강해지셨습니다! 크하핫!', force: true, face: '🐞');
  }

  void _autoUpgrade() {
    final opts = <void Function()>[];
    if (clawLv < 8) opts.add(() => clawLv++);
    if (fangLv < 6) opts.add(() => fangLv++);
    if (roarLv < 7) opts.add(() => roarLv++);
    if (boltLv < 7) opts.add(() => boltLv++);
    if (spikeLv < 7) opts.add(() => spikeLv++);
    opts.add(() => wildLv++);
    opts.add(() {
      hideLv++;
      hp = min(hp + 25, maxHp);
    });
    opts.add(() => windLv++);
    opts.add(() => hungerLv++);
    opts.add(() => rageLv++);
    opts[rng.nextInt(opts.length)]();
  }

  // 조이스틱
  bool jActive = false;
  double jbx = 0, jby = 0, jkx = 0, jky = 0, dirx = 0, diry = 0;

  // 레벨업 강화 선택지
  List<Upgrade> choices = [];

  // 기록
  double bestTime = 0;
  int bestKills = 0;
  // 메타 진행 — 영구 화폐 '송곳니' + 강화 레벨
  int fangs = 0;
  final Map<String, int> meta = {};
  int runFangs = 0; // 이번 런에서 번 송곳니(사망 화면 표시)

  int metaLv(String id) => meta[id] ?? 0;
  int metaCost(String id) {
    final m = kMeta.firstWhere((e) => e.id == id);
    return (m.baseCost * pow(m.growth, metaLv(id))).round();
  }

  bool buyMeta(String id) {
    final m = kMeta.firstWhere((e) => e.id == id);
    if (metaLv(id) >= m.maxLv) return false;
    final c = metaCost(id);
    if (fangs < c) return false;
    fangs -= c;
    meta[id] = metaLv(id) + 1;
    _saveMeta();
    return true;
  }

  // 위협도(현재 난이도 diff 기반) — 스테이지 느낌 표시
  String get threatLabel => diff < 0.85
      ? '안온'
      : diff < 1.15
          ? '평이'
          : diff < 1.5
              ? '거셈'
              : diff < 1.85
                  ? '흉포'
                  : '지옥';
  int get threatStars => (diff / 0.45).clamp(1, 5).floor();
  Color get threatColor => diff < 1.15
      ? P.green
      : diff < 1.5
          ? P.gold
          : diff < 1.85
              ? const Color(0xFFE8702E)
              : P.red;

  // 햅틱 큐 (UI가 소비)
  bool _hapticHit = false, _hapticBig = false;

  World() {
    try {
      slot = (int.tryParse(html.window.localStorage['surv_slot'] ?? '1') ?? 1).clamp(1, 3);
    } catch (_) {}
    _loadRecords();
    _loadMeta();
    _checkDaily();
  }

  // ── 파생 스탯 (캐릭터 배수 + 광폭화 + 영구 강화(meta) 반영) ──
  double get maxHp => (baseMaxHp + 25 * hideLv + 15 * metaLv('hp')) * charHp;
  double get speed =>
      baseSpeed * (1 + 0.10 * windLv + 0.04 * metaLv('spd')) * charSpeed * (berserkT > 0 ? 1.18 : 1.0);
  double get pickupRange => 58 + 16.0 * hungerLv + 8 * metaLv('pick');
  double get dmgMult =>
      (1 + 0.12 * wildLv + 0.05 * metaLv('atk')) * charDmg * (berserkT > 0 ? 1.35 : 1.0);
  double get fireMult => (1 + 0.10 * rageLv) * (berserkT > 0 ? 1.6 : 1.0);
  bool get rageReady => rage >= rageMax;

  void toggleMute() => sfx.muted = !sfx.muted;

  void startGame() {
    sfx.init(); // 사용자 탭(시작 버튼) 직후 → 오디오 정책 통과
    phase = GPhase.playing;
    time = 0;
    kills = 0;
    _mileShown = 0;
    level = 1;
    xp = 0;
    xpNext = 4;
    // 캐릭터 적용
    final ch = kChars[charIndex.clamp(0, kChars.length - 1)];
    charDmg = ch.dmg;
    charHp = ch.hp;
    charSpeed = ch.speed;
    clawLv = ch.startWeapon == 'claw' ? 1 : 0;
    fangLv = ch.startWeapon == 'fang' ? 1 : 0;
    roarLv = ch.startWeapon == 'roar' ? 1 : 0;
    boltLv = 0;
    spikeLv = 0;
    clawEvo = fangEvo = roarEvo = false;
    wildLv = hideLv = windLv = hungerLv = rageLv = 0;
    clawT = 0;
    roarT = 0;
    boltT = 0;
    spikeT = 0;
    spawnT = 1.4; // 첫 몇 초 숨 돌릴 여유
    bossT = 90;
    orbitAngle = 0;
    enemies.clear();
    bullets.clear();
    orbs.clear();
    parts.clear();
    pulses.clear();
    floats.clear();
    lines.clear();
    shake = 0;
    px = w / 2;
    py = h / 2;
    hp = maxHp;
    rage = 0;
    berserkT = 0;
    petX = px - 20;
    petY = py - 22;
    petHappyT = 0;
    devour = 0;
    runBoss = 0;
    pendingAch.clear();
    heraldLine = '';
    heraldT = 0;
    _heraldCd = 0;
    _lowCd = 0;
    _streakKillMark = 0;
    diff = 1.0;
    tinyChoice = null;
    _choiceCd = 14;
    _advT = 48;
    jActive = false;
    dirx = diry = 0;
    _say(_pick(Tiny.greet), force: true, face: '🐯');
  }

  // 광기 해방 — 어흥! 화면 전체 대포효 + 광폭화
  void unleashRoar() {
    if (phase != GPhase.playing || !rageReady) return;
    rage = 0;
    berserkT = 5.0;
    final dmg = 60 + level * 12.0;
    for (final e in enemies) {
      _hurt(e, dmg);
      final d = sqrt((e.x - px) * (e.x - px) + (e.y - py) * (e.y - py));
      if (d > 0.1) {
        e.x += (e.x - px) / d * 70;
        e.y += (e.y - py) / d * 70;
      }
    }
    pulses.add(Pulse(px, py, max(w, h), 0.55, P.gold));
    pulses.add(Pulse(px, py, max(w, h) * 0.6, 0.45, P.blood));
    _float(px, py - 30, '어 흥 !!', P.gold, 30);
    _say(_pick(Tiny.ult), force: true, face: '🔥');
    _shakeAdd(18);
    _hapticBig = true;
    sfx.play('boss');
  }

  // 적 일부 제거(후퇴 시 숨통) — 보스는 제외
  void _thin(double frac) {
    enemies.removeWhere((e) => e.type != EType.boss && rng.nextDouble() < frac);
  }

  void _offerRetreat() {
    phase = GPhase.choice;
    tinyChoice = TinyChoice(
      '대장님, 여긴 좀 거셉니다. 2보 전진을 위한 1보 후퇴… 잠시 수월한 사냥터로 물러날까요?',
      '🐾 잠시 물러난다', '난이도↓·체력 회복·숨통',
      () {
        diff = max(0.6, diff - 0.4);
        hp = min(maxHp, hp + maxHp * 0.35);
        _thin(0.55);
        _say('현명하십니다. 호랑이는 물러설 때를 아는 법이죠.', force: true, face: '🐯');
      },
      '🔥 계속 사냥한다', '그대로 — 위험하지만 멋짐',
      () {
        rage = min(rageMax, rage + rageMax * 0.3);
        _say('크하핫—! 역시 호랑이답습니다, 물러섬을 모르는 분!', force: true, face: '😼');
      },
    );
  }

  void _offerAdvance() {
    phase = GPhase.choice;
    tinyChoice = TinyChoice(
      '대장님껜 이 잡것들이 시시하시죠? 더 사나운 놈들의 둥지로 쳐들어가 볼까요?',
      '🐅 더 사나운 곳으로', '성장↑·위험↑ (방심하면 한 입)',
      () {
        diff = min(2.2, diff + 0.45);
        _say('이래야 사냥할 맛이 나죠! 단— 방심하면 한 입에 끝납니다.', force: true, face: '😼');
      },
      '🌿 천천히 간다', '변동 없음 — 신중',
      () => _say('신중함도 맹수의 덕목이죠.', force: true, face: '🐯'),
    );
  }

  void pickChoice(bool right) {
    final c = tinyChoice;
    if (c == null) return;
    (right ? c.onRight : c.onLeft)();
    tinyChoice = null;
    _choiceCd = 32;
    phase = GPhase.playing;
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
    final dx = x - jbx, dy = y - jby;
    final len = sqrt(dx * dx + dy * dy);
    const maxR = 50.0, dead = 5.0;
    if (len < dead) {
      jkx = x;
      jky = y;
      dirx = diry = 0;
      return;
    }
    final knob = len > maxR ? maxR : len;
    jkx = jbx + dx / len * knob;
    jky = jby + dy / len * knob;
    dirx = dx / len; // 데드존만 넘으면 즉시 풀스피드 방향 (반응 깔끔)
    diry = dy / len;
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
    if (berserkT > 0) berserkT = max(0, berserkT - dt);
    // 펫 타이니 — 플레이어 좌상단을 부드럽게 따라다님
    if (petHappyT > 0) petHappyT = max(0, petHappyT - dt);
    final k = (dt * 7).clamp(0.0, 1.0);
    petX += (px - 20 - petX) * k;
    petY += (py - 24 - petY) * k;
    // 충신 타이머
    if (heraldT > 0) heraldT -= dt;
    if (_heraldCd > 0) _heraldCd -= dt;
    if (_lowCd > 0) _lowCd -= dt;
    // 생존 마일스톤 — 충신이 떠받든다
    if (_mileShown < 1 && time >= 60) {
      _mileShown = 1;
      _say('1분 생존! 대륙이 대장님의 포효를 듣기 시작했습니다!', force: true, face: '🌟');
    } else if (_mileShown < 2 && time >= 120) {
      _mileShown = 2;
      _say('2분! 이제 그림자 의회가 대장님 이름만 들어도 떱니다!', force: true, face: '🌟');
    } else if (_mileShown < 3 && time >= 180) {
      _mileShown = 3;
      _say('3분 생존… 대장님은 이미 살아있는 전설이십니다!', force: true, face: '🌟');
    }
    // 위기 시 가스라이팅성 응원
    if (_lowCd <= 0 && hp < maxHp * 0.25) {
      _lowCd = 9;
      _say(_pick(Tiny.low), face: '😿');
    }
    // 학살 연쇄
    if (kills - _streakKillMark >= 30) {
      _streakKillMark = kills;
      _say(_pick(Tiny.streak), face: '😼');
    }
    // 타이니 난이도 선택 제안 (쿨다운 기반)
    if (_choiceCd > 0) _choiceCd -= dt;
    if (_advT > 0) _advT -= dt;
    if (_choiceCd <= 0) {
      if (hp < maxHp * 0.32 && diff > 0.65) {
        _offerRetreat();
        return;
      } else if (hp > maxHp * 0.6 && _advT <= 0 && diff < 2.0 && time > 40) {
        _advT = 55;
        _offerAdvance();
        return;
      }
    }

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
      xpNext = (xpNext * 1.26 + 2).roundToDouble();
      _hapticBig = true;
      _shakeAdd(9);
      petHappyT = 1.6; // 펫이 신남
      sfx.play('level');
      _say(_pick(Tiny.level), force: true, face: '😺');
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
    final interval = max(0.5, 2.0 - time * 0.011).toDouble();
    spawnT = interval;
    if (enemies.length > 120) return;
    final count = 1 + (time ~/ 48);
    for (int i = 0; i < count; i++) {
      if (enemies.length > 120) break;
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
    // 타입 결정 (시간에 따라 흉포해짐) — 초반은 잡몹만, 점진적으로 강적 등장
    EType t = EType.grunt;
    final roll = rng.nextDouble();
    if (time > 78 && roll < 0.13) {
      t = EType.tank;
    } else if (time > 42 && roll < 0.32) {
      t = EType.fast;
    }
    final base = (9 + time * 0.5) * diff;
    Enemy e;
    if (t == EType.fast) {
      e = Enemy(_eid++, x, y, base * 0.65, base * 0.65, 72 + time * 0.17, (4 + time * 0.03) * diff, 9, t);
    } else if (t == EType.tank) {
      e = Enemy(_eid++, x, y, base * 3.0, base * 3.0, 30 + time * 0.05, (8.5 + time * 0.05) * diff, 18, t);
    } else {
      e = Enemy(_eid++, x, y, base, base, 44 + time * 0.12, (4.5 + time * 0.03) * diff, 11, t);
    }
    enemies.add(e);
  }

  void _spawnBoss() {
    final x = px + (rng.nextBool() ? 1 : -1) * w * 0.5;
    final y = py + (rng.nextBool() ? 1 : -1) * h * 0.4;
    final base = (240 + time * 6) * diff;
    enemies.add(Enemy(_eid++, x.clamp(0.0, w), y.clamp(0.0, h), base, base, 40, (22 + time * 0.08) * diff, 30, EType.boss));
    pulses.add(Pulse(px, py, 200, 0.6, P.blood));
    _float(px, py - 60, '⚠ 의회의 거대 맹수 강림', P.red, 18);
    _shakeAdd(12);
    _hapticBig = true;
    sfx.play('boss');
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
    // 발톱 폭풍 (투사체) — 진화 시 '천 개의 발톱': 전방위 난사
    if (clawLv > 0) {
      clawT -= dt;
      if (clawT <= 0) {
      clawT = ((clawEvo ? 0.5 : 0.8 * pow(0.9, clawLv - 1)) / fireMult).toDouble();
      final target = _nearest();
      if ((target != null || clawEvo) && bullets.length < 320) {
        final dmg = (9 + clawLv * 4) * dmgMult * (clawEvo ? 1.7 : 1.0);
        final pierce = clawEvo ? 3 : (clawLv >= 5 ? 1 : 0);
        if (clawEvo) {
          for (int i = 0; i < 16; i++) {
            final a = orbitAngle * 0.4 + i * 6.2831853 / 16;
            bullets.add(Bullet(px, py, cos(a) * 360, sin(a) * 360, dmg, 6, 1.5, pierce));
          }
        } else {
          final n = 1 + (clawLv >= 2 ? 1 : 0) + (clawLv >= 4 ? 1 : 0) + (clawLv >= 6 ? 1 : 0);
          final baseAng = atan2(target!.y - py, target.x - px);
          for (int i = 0; i < n; i++) {
            final a = baseAng + (i - (n - 1) / 2) * 0.18;
            bullets.add(Bullet(px, py, cos(a) * 340, sin(a) * 340, dmg, 6, 1.4, pierce));
          }
        }
        sfx.play('shoot', gapMs: 60);
      }
      }
    }
    // 벼락 (연쇄 번개)
    if (boltLv > 0) {
      boltT -= dt;
      if (boltT <= 0) {
        boltT = ((1.5 * pow(0.9, boltLv - 1)) / fireMult).toDouble();
        if (enemies.isNotEmpty) {
          double dmg = (10 + boltLv * 6) * dmgMult;
          double fx = px, fy = py;
          final chain = 1 + boltLv;
          final hitSet = <int>{};
          for (int c = 0; c < chain; c++) {
            Enemy? nxt;
            double bd = 210.0 * 210.0;
            for (final e in enemies) {
              if (e.dead || hitSet.contains(e.id)) continue;
              final d = (e.x - fx) * (e.x - fx) + (e.y - fy) * (e.y - fy);
              if (d < bd) {
                bd = d;
                nxt = e;
              }
            }
            if (nxt == null) break;
            lines.add(LineFx(fx, fy, nxt.x, nxt.y, P.cyan));
            _hurt(nxt, dmg);
            _float(nxt.x, nxt.y - nxt.radius, dmg.round().toString(), P.cyan, 12);
            hitSet.add(nxt.id);
            fx = nxt.x;
            fy = nxt.y;
            dmg *= 0.82;
          }
          sfx.play('hit', gapMs: 30);
        }
      }
    }
    // 가시밭 (주기적 광역 지대)
    if (spikeLv > 0) {
      spikeT -= dt;
      if (spikeT <= 0) {
        spikeT = ((1.8 * pow(0.92, spikeLv - 1)) / fireMult).toDouble();
        final radius = 42 + spikeLv * 7.0;
        final dmg = (8 + spikeLv * 5) * dmgMult;
        final ox = px + (rng.nextDouble() - 0.5) * 160;
        final oy = py + (rng.nextDouble() - 0.5) * 160;
        for (final e in enemies) {
          final rr = radius + e.radius;
          if ((e.x - ox) * (e.x - ox) + (e.y - oy) * (e.y - oy) <= rr * rr) {
            _hurt(e, dmg);
          }
        }
        pulses.add(Pulse(ox, oy, radius, 0.5, P.green));
      }
    }
    // 포효 (충격파 — 즉발 광역)
    if (roarLv > 0) {
      roarT -= dt;
      if (roarT <= 0) {
        final cd = (2.6 * pow(0.93, roarLv - 1)) / fireMult;
        roarT = cd.toDouble();
        final radius = (70 + roarLv * 16.0) * (roarEvo ? 1.8 : 1.0);
        final dmg = (8 + roarLv * 6) * dmgMult * (roarEvo ? 2.2 : 1.0);
        final push = roarEvo ? 30.0 : 14.0;
        for (final e in enemies) {
          final d = sqrt((e.x - px) * (e.x - px) + (e.y - py) * (e.y - py));
          if (d <= radius + e.radius) {
            _hurt(e, dmg);
            // 살짝 밀어내기
            if (d > 0.1) {
              e.x += (e.x - px) / d * push;
              e.y += (e.y - py) / d * push;
            }
          }
        }
        pulses.add(Pulse(px, py, radius, 0.45, P.gold));
        _shakeAdd(5);
        sfx.play('roar');
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
          _float(e.x, e.y - e.radius - 4, b.dmg.round().toString(), P.goldSoft, 13);
          sfx.play('hit', gapMs: 45);
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

    // 회전 송곳니 vs 적 (지속 DPS) — 진화 시 '죽음의 고리'
    if (fangLv > 0) {
      final cnt = fangLv + (fangEvo ? 3 : 0);
      final orad = (60 + fangLv * 4.0) * (fangEvo ? 1.4 : 1.0);
      final fdps = (22 + fangLv * 14) * dmgMult * (fangEvo ? 1.9 : 1.0);
      final fr = fangEvo ? 17.0 : 13.0;
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
        _shakeAdd(3);
      }
    }

    // 죽은 적 처리 → 구슬/파티클
    for (final e in enemies) {
      if (e.hp <= 0 && !e.dead) {
        e.dead = true;
        kills += 1;
        petHappyT = 1.0; // 펫이 기뻐함
        // [포식] 삼켜서 회복 + 성장
        devour += 1;
        final heal = e.type == EType.boss
            ? 12.0
            : (e.type == EType.tank ? 2.5 : (e.type == EType.fast ? 0.4 : 0.6));
        if (hp < maxHp) {
          hp = min(maxHp, hp + heal);
          if (heal >= 2.5) _float(e.x, e.y - e.radius, '+${heal.round()}♥', P.green, 13);
        }
        rage = min(rageMax, rage + (e.type == EType.boss ? 14 : (e.type == EType.tank ? 3 : 1)) * diff);
        if (e.type == EType.boss) {
          runBoss += 1;
          _float(e.x, e.y - e.radius, 'BOSS 격파!', P.gold, 18);
          _say(_pick(Tiny.boss), force: true, face: '😼');
          _shakeAdd(10);
          _hapticBig = true;
        }
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
          xp += o.value * diff; // 난이도 높을수록 경험치 ↑(빠른 성장)
          o.dead = true;
          sfx.play('pick', gapMs: 35);
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
    for (final f in floats) {
      f.y -= 38 * dt;
      f.life -= dt;
    }
    floats.removeWhere((f) => f.life <= 0);
    for (final l in lines) {
      l.life -= dt;
    }
    lines.removeWhere((l) => l.life <= 0);
    if (shake > 0) shake = max(0, shake - dt * 26);
  }

  // ── 레벨업 강화 ──
  void _openLevelUp() {
    phase = GPhase.levelup;

    // [진화] 무기 최대 레벨 + 시너지 패시브 → 초월 무기 (뱀서의 핵심 훅, 우선 노출)
    final evos = <Upgrade>[];
    if (clawLv >= 8 && rageLv >= 3 && !clawEvo) {
      evos.add(Upgrade('🌩', '진화! 천 개의 발톱', '발톱이 전방위로 폭주한다 (발톱 Lv8 + 분노)',
          () => clawEvo = true));
    }
    if (fangLv >= 6 && wildLv >= 3 && !fangEvo) {
      evos.add(Upgrade('☠', '진화! 죽음의 고리', '송곳니 +3·거대화·맹독 DPS (송곳니 Lv6 + 야성)',
          () => fangEvo = true));
    }
    if (roarLv >= 7 && hideLv >= 3 && !roarEvo) {
      evos.add(Upgrade('🌋', '진화! 대지진', '포효가 대륙을 가른다 — 범위·위력 폭증 (포효 Lv7 + 가죽)',
          () => roarEvo = true));
    }

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
    if (boltLv < 7) {
      pool.add(Upgrade('⚡', '벼락', boltLv == 0 ? '가까운 적들에게 연쇄하는 번개' : '연쇄·위력 강화 (Lv ${boltLv + 1})',
          () => boltLv++));
    }
    if (spikeLv < 7) {
      pool.add(Upgrade('🌵', '가시밭', spikeLv == 0 ? '바닥에 주기적으로 솟는 가시 지대' : '범위·위력 강화 (Lv ${spikeLv + 1})',
          () => spikeLv++));
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

    // 진화는 항상 먼저 노출 + 나머지는 무작위로 채워 3~4개 제시
    final out = <Upgrade>[...evos];
    for (final u in pool) {
      if (out.length >= (evos.isNotEmpty ? 4 : 3)) break;
      out.add(u);
    }
    choices = out;
  }

  void pick(Upgrade u) {
    u.apply();
    choices = [];
    phase = GPhase.playing;
  }

  void _onDeath() {
    phase = GPhase.dead;
    _hapticBig = true;
    sfx.play('death');
    if (time > bestTime) bestTime = time;
    if (kills > bestKills) bestKills = kills;
    // 전리품 적립 — 죽음이 헛되지 않게(플레이한 만큼 보상)
    runFangs = ((kills + time.floor() + level * 8) * (1 + 0.12 * metaLv('gain'))).round();
    fangs += runFangs;
    _evalAchievements();
    _saveRecords();
    _saveMeta();
  }

  void _grantAch(String id, int reward) {
    if (achieved.contains(id)) return;
    achieved.add(id);
    fangs += reward;
    runFangs += reward;
    pendingAch.add(id);
  }

  void _evalAchievements() {
    pendingAch.clear();
    if (kills >= 10) _grantAch('kill10', 10);
    if (time >= 60) _grantAch('surv60', 15);
    if (level >= 10) _grantAch('lv10', 20);
    if (stage >= 5) _grantAch('stage5', 25);
    if (kills >= 100) _grantAch('kill100', 25);
    if (runBoss >= 1) _grantAch('boss1', 30);
    if (devour >= 200) _grantAch('dev200', 30);
    if (time >= 180) _grantAch('surv180', 40);
  }

  // ── 세이브 슬롯 (3개) — 슬롯별 송곳니·강화·기록 분리 저장 ──
  int slot = 1;
  String get _metaKey => 'surv_meta_$slot';
  String get _recKey => 'surv_rec_$slot';

  void selectSlot(int s) {
    slot = s.clamp(1, 3);
    try {
      html.window.localStorage['surv_slot'] = slot.toString();
    } catch (_) {}
    fangs = 0;
    meta.clear();
    achieved.clear();
    ownedSkins
      ..clear()
      ..add('default');
    skin = 'default';
    lastDaily = '';
    dailyJustClaimed = false;
    bestTime = 0;
    bestKills = 0;
    _loadRecords();
    _loadMeta();
    _checkDaily();
  }

  // 데일리 보너스 — 하루 첫 접속 시 송곳니 +30 (리텐션, 비강제)
  void _checkDaily() {
    try {
      final n = DateTime.now();
      final today =
          '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
      if (lastDaily != today) {
        lastDaily = today;
        fangs += 30;
        dailyJustClaimed = true;
        _saveMeta();
      }
    } catch (_) {}
  }

  // 슬롯 요약(없으면 null) — 타이틀 슬롯 선택용
  Map<String, dynamic>? slotInfo(int s) {
    try {
      final rec = html.window.localStorage['surv_rec_$s'];
      final mt = html.window.localStorage['surv_meta_$s'];
      if (rec == null && mt == null) return null;
      int f = 0;
      double bt = 0;
      if (mt != null) f = ((jsonDecode(mt) as Map)['fangs'] as int?) ?? 0;
      if (rec != null) bt = (((jsonDecode(rec) as Map)['bt']) as num?)?.toDouble() ?? 0;
      return {'fangs': f, 'bt': bt};
    } catch (_) {
      return null;
    }
  }

  void _loadMeta() {
    try {
      final raw = html.window.localStorage[_metaKey];
      if (raw == null) return;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      fangs = j['fangs'] as int? ?? 0;
      final m = (j['up'] as Map?) ?? {};
      m.forEach((k, v) => meta[k as String] = v as int);
      achieved.addAll(((j['ach'] as List?) ?? []).map((e) => e as String));
      ownedSkins.addAll(((j['skins'] as List?) ?? []).map((e) => e as String));
      skin = j['skin'] as String? ?? 'default';
      lastDaily = j['daily'] as String? ?? '';
    } catch (_) {}
  }

  void _saveMeta() {
    try {
      html.window.localStorage[_metaKey] = jsonEncode({
        'fangs': fangs,
        'up': meta,
        'ach': achieved.toList(),
        'skins': ownedSkins.toList(),
        'skin': skin,
        'daily': lastDaily,
      });
    } catch (_) {}
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
      final raw = html.window.localStorage[_recKey];
      if (raw == null) return;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      bestTime = (j['bt'] as num?)?.toDouble() ?? 0;
      bestKills = j['bk'] as int? ?? 0;
    } catch (_) {}
  }

  void _saveRecords() {
    try {
      html.window.localStorage[_recKey] = jsonEncode({'bt': bestTime, 'bk': bestKills});
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
            if (world.phase == GPhase.playing ||
                world.phase == GPhase.levelup ||
                world.phase == GPhase.choice ||
                world.phase == GPhase.menu) _hud(),
            if (world.phase == GPhase.playing) _rageButton(),
            if (world.phase == GPhase.playing) _tinyCallButton(),
            if (world.phase == GPhase.playing && world.heraldT > 0) _heraldBubble(),
            if (world.phase == GPhase.title) _title(),
            if (world.phase == GPhase.shop) _shopOverlay(),
            if (world.phase == GPhase.achieve) _achieveOverlay(),
            if (world.phase == GPhase.skins) _skinsOverlay(),
            if (world.phase == GPhase.menu) _menuOverlay(),
            if (world.phase == GPhase.levelup) _levelUp(),
            if (world.phase == GPhase.choice && world.tinyChoice != null) _choiceOverlay(),
            if (world.phase == GPhase.dead) _death(),
            // (음소거는 타이니 메뉴로 이동)
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
              const SizedBox(width: 6),
              _tag('Lv ${world.level}', color: P.gold),
              const SizedBox(width: 6),
              _tag('🌊 STAGE ${world.stage}', color: world.threatColor),
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

  // ── 충신 '타이니' 말풍선 (상단, 무음 텍스트) ──
  Widget _heraldBubble() {
    final ht = world.heraldT;
    final appear = ((3.2 - ht) / 0.22).clamp(0.0, 1.0); // 등장 진행 0→1
    final fade = ht > 0.5 ? 1.0 : (ht / 0.5).clamp(0.0, 1.0);
    final pop = 0.82 + 0.18 * appear + sin(appear * 3.1416) * 0.07; // 살짝 오버슈트 팝
    final bounce = sin(world.time * 6) * 2.2; // 타이니 얼굴 통통
    return Positioned(
      top: 80,
      left: 12,
      right: 12,
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: pop,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                decoration: BoxDecoration(
                  color: const Color(0xA6140E09), // 반투명 — 뒤 적이 보이게
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: P.gold.withOpacity(0.9), width: 1.6),
                  boxShadow: [BoxShadow(color: P.gold.withOpacity(0.35), blurRadius: 10)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // 통통 튀는 타이니 얼굴 (표정으로 톤 전달 — 안 읽어도 인식)
                  Transform.translate(
                    offset: Offset(0, bounce),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: P.gold.withOpacity(0.22),
                        border: Border.all(color: P.gold.withOpacity(0.85)),
                      ),
                      child: Text(world.heraldFace, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('타이니',
                            style: TextStyle(
                                color: P.gold, fontSize: 9.5, fontWeight: FontWeight.bold)),
                        Text(world.heraldLine,
                            style: const TextStyle(
                                color: P.goldSoft,
                                fontSize: 12.5,
                                height: 1.25,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 타이니 호출 버튼 (시리/빅스비식) — 어흥 버튼 위(좌하단). 누르기 전 살짝 반투명 ──
  Widget _tinyCallButton() {
    return Positioned(
      left: 34,
      bottom: 110,
      child: GestureDetector(
        onTap: () => setState(() => world.openMenu()),
        child: Opacity(
          opacity: 0.62,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.45),
              border: Border.all(color: P.gold.withOpacity(0.75), width: 1.5),
            ),
            child: const Text('🐯', style: TextStyle(fontSize: 22)),
          ),
        ),
      ),
    );
  }

  // ── 타이니 메뉴 (호출 시) — 난이도 정보 + 상점/음소거/포기 ──
  Widget _menuOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🐯 타이니', style: TextStyle(color: P.gold, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('부르셨습니까, 대장님?', style: TextStyle(color: P.muted, fontSize: 12)),
        const SizedBox(height: 16),
        Container(
          width: 300,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: P.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: world.threatColor.withOpacity(0.7)),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('현재 스테이지', style: TextStyle(color: P.muted, fontSize: 12)),
              Text('STAGE ${world.stage}',
                  style: TextStyle(color: world.threatColor, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('적 강함', style: TextStyle(color: P.muted, fontSize: 12)),
              Text('×${world.diff.toStringAsFixed(2)}',
                  style: TextStyle(color: world.threatColor, fontSize: 14, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('생존 · 처치', style: TextStyle(color: P.muted, fontSize: 12)),
              Text('${World.mmss(world.time)} · ${world.kills}',
                  style: const TextStyle(color: P.parch, fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
          ]),
        ),
        const SizedBox(height: 18),
        _bigBtn('▶  이어하기', P.gold, () => setState(() => world.resume())),
        const SizedBox(height: 10),
        _bigBtn('🦷  전리품 상점', P.panel, () => setState(() {
              world.shopReturn = GPhase.menu;
              world.phase = GPhase.shop;
            }), dark: false),
        const SizedBox(height: 10),
        _bigBtn('🏳  포기하고 마치기', P.blood, () => setState(() => world.giveUp()), dark: false),
        const SizedBox(height: 10),
        // [내부 테스트 치트] 타이니 +10 레벨
        _bigBtn('🐞  치트: +10 레벨', const Color(0xFF2A3A2A),
            () => setState(() => world.cheatLevel10()), dark: false),
      ]),
    );
  }

  // ── 어흥! 광기 궁극기 버튼 (우하단) ──
  Widget _rageButton() {
    final frac = (world.rage / world.rageMax).clamp(0.0, 1.0);
    final ready = world.rageReady;
    return Positioned(
      left: 18,
      bottom: 22,
      child: GestureDetector(
        onTap: () {
          if (ready) setState(() => world.unleashRoar());
        },
        child: Opacity(
          opacity: ready ? 1.0 : 0.45, // 가득 차기 전엔 반투명, 차면 불투명
          child: SizedBox(
          width: 78,
          height: 78,
          child: Stack(alignment: Alignment.center, children: [
            // 충전 링
            SizedBox(
              width: 78,
              height: 78,
              child: CircularProgressIndicator(
                value: frac,
                strokeWidth: 6,
                backgroundColor: Colors.black.withOpacity(0.45),
                valueColor: AlwaysStoppedAnimation(ready ? P.gold : P.blood),
              ),
            ),
            // 본체
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ready ? P.gold.withOpacity(0.92) : Colors.black.withOpacity(0.5),
                boxShadow: ready
                    ? [BoxShadow(color: P.gold.withOpacity(0.7), blurRadius: 14)]
                    : null,
                border: Border.all(color: ready ? Colors.white : P.line, width: 1.5),
              ),
              child: Text('어흥',
                  style: TextStyle(
                      color: ready ? Colors.black : P.muted,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
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
    final sel = kChars[world.charIndex.clamp(0, kChars.length - 1)];
    return Container(
      color: Colors.black.withOpacity(0.62),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          const Text('어흥 : 야수의 생존',
              style: TextStyle(
                  color: P.gold, fontSize: 27, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 10),
          const Text('그림자 의회가 네 둥지를 불태우고 무리를 끌고 갔다.\n살아남은 건 너 하나. 이제 — 사냥의 시간이다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: P.parch, fontSize: 13, height: 1.6)),
          const SizedBox(height: 6),
          const Text('드래그로 이동 · 공격 자동 · 광기가 차면 [어흥!]',
              textAlign: TextAlign.center,
              style: TextStyle(color: P.muted, fontSize: 12)),
          const SizedBox(height: 18),
          const Text('세이브 슬롯',
              style: TextStyle(color: P.parch, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final n = i + 1;
              final on = world.slot == n;
              final info = world.slotInfo(n);
              return GestureDetector(
                onTap: () => setState(() => world.selectSlot(n)),
                child: Container(
                  width: 98,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
                  decoration: BoxDecoration(
                    color: on ? P.gold.withOpacity(0.16) : Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: on ? P.gold : P.line, width: on ? 2 : 1),
                  ),
                  child: Column(children: [
                    Text('슬롯 $n',
                        style: TextStyle(
                            color: on ? Colors.white : P.muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(
                        info == null
                            ? '빈 슬롯'
                            : '🦷${info['fangs']}\n최고 ${World.mmss((info['bt'] as num).toDouble())}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: P.muted, fontSize: 10, height: 1.3)),
                  ]),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          const Text('맹수를 고르십시오',
              style: TextStyle(color: P.parch, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(kChars.length, (i) {
              final c = kChars[i];
              final on = i == world.charIndex;
              return GestureDetector(
                onTap: () => setState(() => world.charIndex = i),
                child: Container(
                  width: 92,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    color: on ? c.color.withOpacity(0.16) : Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: on ? c.color : P.line, width: on ? 2.2 : 1),
                  ),
                  child: Column(children: [
                    Text(c.icon, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 5),
                    Text(c.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: on ? Colors.white : P.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: Text(sel.desc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: P.parch, fontSize: 12.5, height: 1.4)),
          ),
          const SizedBox(height: 6),
          if (world.bestTime > 0)
            Text('최고 기록 ${World.mmss(world.bestTime)} · ${world.bestKills}킬',
                style: const TextStyle(color: P.muted, fontSize: 12)),
          const SizedBox(height: 22),
          _bigBtn('⚔  생존 시작', sel.color, () => setState(() => world.startGame())),
          const SizedBox(height: 12),
          _bigBtn('🦷  전리품 상점  (보유 ${world.fangs})', P.panel, () => setState(() {
                world.shopReturn = GPhase.title;
                world.phase = GPhase.shop;
              }), dark: false),
          const SizedBox(height: 10),
          _bigBtn('🏆  업적  (${world.achieved.length}/${kAch.length})', P.panel,
              () => setState(() => world.phase = GPhase.achieve),
              dark: false),
          const SizedBox(height: 10),
          _bigBtn('🎀  스킨  (${world.ownedSkins.length}/${kSkins.length})', P.panel,
              () => setState(() => world.phase = GPhase.skins),
              dark: false),
          if (world.dailyJustClaimed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x22E8A33D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: P.gold.withOpacity(0.6)),
              ),
              child: const Text('🎁 오늘의 보너스 +30 🦷 받았습니다!',
                  style: TextStyle(color: P.goldSoft, fontSize: 12.5, fontWeight: FontWeight.bold)),
            ),
          ],
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  // ── 전리품 상점 (영구 강화) ──
  Widget _shopOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.82),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(children: [
              const Text('🦷 전리품 상점',
                  style: TextStyle(color: P.gold, fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('보유 🦷 ${world.fangs}',
                  style: const TextStyle(color: P.goldSoft, fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
          ),
          const Text('죽음은 헛되지 않는다 — 사냥한 만큼 영원히 강해진다',
              style: TextStyle(color: P.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: kMeta.map((m) {
                final lv = world.metaLv(m.id);
                final maxed = lv >= m.maxLv;
                final cost = world.metaCost(m.id);
                final afford = !maxed && world.fangs >= cost;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: P.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: P.line),
                    ),
                    child: Row(children: [
                      Text(m.icon, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${m.name}  Lv $lv/${m.maxLv}',
                              style: const TextStyle(
                                  color: P.parch, fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(m.desc, style: const TextStyle(color: P.muted, fontSize: 11.5)),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 86,
                        child: Material(
                          color: maxed
                              ? const Color(0xFF2A2018)
                              : (afford ? P.gold : const Color(0xFF2A2018)),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: afford
                                ? () => setState(() => world.buyMeta(m.id))
                                : null,
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              child: Text(maxed ? 'MAX' : '🦷 $cost',
                                  style: TextStyle(
                                      color: maxed
                                          ? P.muted
                                          : (afford ? Colors.black : P.muted),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: _bigBtn('← 돌아가기', P.panel,
                () => setState(() => world.phase = world.shopReturn),
                dark: false),
          ),
        ]),
      ),
    );
  }

  // ── 코스메틱 스킨 ──
  Widget _skinsOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.82),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(children: [
              const Text('🎀 스킨',
                  style: TextStyle(color: P.gold, fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('보유 🦷 ${world.fangs}',
                  style: const TextStyle(color: P.goldSoft, fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              children: kSkins.map((s) {
                final owned = world.ownedSkins.contains(s.id);
                final on = world.skin == s.id;
                final swatch =
                    s.id == 'default' ? kChars[world.charIndex.clamp(0, kChars.length - 1)].color : s.color;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: on ? P.gold.withOpacity(0.14) : P.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: on ? P.gold : P.line, width: on ? 2 : 1),
                    ),
                    child: Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: swatch,
                          boxShadow: [BoxShadow(color: swatch.withOpacity(0.6), blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('${s.icon} ${s.name}',
                            style: const TextStyle(
                                color: P.parch, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(
                        width: 90,
                        child: Material(
                          color: on
                              ? const Color(0xFF2A2018)
                              : (owned ? P.green.withOpacity(0.85) : (world.fangs >= s.cost ? P.gold : const Color(0xFF2A2018))),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: on
                                ? null
                                : () => setState(
                                    () => owned ? world.selectSkin(s.id) : world.buySkin(s.id)),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              child: Text(
                                  on ? '착용 중' : (owned ? '착용' : '🦷${s.cost}'),
                                  style: TextStyle(
                                      color: on
                                          ? P.muted
                                          : (owned ? Colors.black : (world.fangs >= s.cost ? Colors.black : P.muted)),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: _bigBtn('← 돌아가기', P.panel, () => setState(() => world.phase = GPhase.title),
                dark: false),
          ),
        ]),
      ),
    );
  }

  // ── 업적 ──
  Widget _achieveOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.82),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(children: [
              const Text('🏆 업적',
                  style: TextStyle(color: P.gold, fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${world.achieved.length} / ${kAch.length}',
                  style: const TextStyle(color: P.goldSoft, fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              children: kAch.map((a) {
                final got = world.achieved.contains(a.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: got ? P.gold.withOpacity(0.12) : P.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: got ? P.gold.withOpacity(0.7) : P.line),
                    ),
                    child: Row(children: [
                      Opacity(opacity: got ? 1 : 0.4, child: Text(a.icon, style: const TextStyle(fontSize: 24))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(got ? a.name : '???',
                              style: TextStyle(
                                  color: got ? P.parch : P.muted, fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(a.desc, style: const TextStyle(color: P.muted, fontSize: 11.5)),
                        ]),
                      ),
                      Text(got ? '✓' : '🦷${a.reward}',
                          style: TextStyle(
                              color: got ? P.green : P.goldSoft, fontSize: 13, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: _bigBtn('← 돌아가기', P.panel, () => setState(() => world.phase = GPhase.title),
                dark: false),
          ),
        ]),
      ),
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
        const SizedBox(height: 4),
        Text('Lv ${world.level}', style: const TextStyle(color: P.muted, fontSize: 13)),
        const SizedBox(height: 12),
        // 타이니가 레벨업마다 떠받든다 (뽕)
        Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: P.gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: P.gold.withOpacity(0.6)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(world.heraldFace, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 9),
            Flexible(
              child: Text(world.heraldLine.isEmpty ? '또 강해지셨습니까, 대장님!' : world.heraldLine,
                  style: const TextStyle(
                      color: P.goldSoft, fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        ...world.choices.map((u) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _upgradeCard(u),
            )),
      ]),
    );
  }

  // ── 타이니 난이도 선택 대화 ──
  Widget _choiceOverlay() {
    final c = world.tinyChoice!;
    return Container(
      color: Colors.black.withOpacity(0.78),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🐯 타이니',
            style: TextStyle(color: P.gold, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(c.prompt,
              textAlign: TextAlign.center,
              style: const TextStyle(color: P.parch, fontSize: 15, height: 1.6)),
        ),
        const SizedBox(height: 20),
        _choiceCard(c.leftLabel, c.leftSub, P.cyan, () => setState(() => world.pickChoice(false))),
        const SizedBox(height: 12),
        _choiceCard(c.rightLabel, c.rightSub, P.blood, () => setState(() => world.pickChoice(true))),
      ]),
    );
  }

  Widget _choiceCard(String label, String sub, Color color, VoidCallback onTap) {
    return Material(
      color: P.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.8), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(sub, style: const TextStyle(color: P.muted, fontSize: 12)),
          ]),
        ),
      ),
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
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x22E8A33D),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('🦷 전리품 +${world.runFangs}  (보유 ${world.fangs})',
                  style: const TextStyle(
                      color: P.goldSoft, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            if (world.pendingAch.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('🏆 새 업적 ${world.pendingAch.length}개 달성!',
                  style: const TextStyle(color: P.green, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        _bigBtn('🔥  다시 일어선다', P.blood, () => setState(() => world.startGame()), dark: false),
        const SizedBox(height: 10),
        _bigBtn('🦷  전리품 상점', P.panel, () => setState(() {
              world.shopReturn = GPhase.dead;
              world.phase = GPhase.shop;
            }), dark: false),
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
//  월드 페인터 — 네온 벡터 (어두운 배경 + 발광 레이어). 전부 코드 생성.
// =============================================================================
class WorldPainter extends CustomPainter {
  final World w;
  WorldPainter(this.w);

  // 발광 점: 큰 후광 → 작은 후광 → 밝은 코어 (HTML 렌더러 호환, maskFilter 미사용)
  void _glow(Canvas c, double x, double y, double r, Color col, {double core = 1.0}) {
    c.drawCircle(Offset(x, y), r * 2.6, Paint()..color = col.withOpacity(0.09));
    c.drawCircle(Offset(x, y), r * 1.6, Paint()..color = col.withOpacity(0.18));
    c.drawCircle(Offset(x, y), r, Paint()..color = col.withOpacity(core));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 배경(흔들림 영향 X)
    final bg = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF15110C), Color(0xFF070605)],
        radius: 1.0,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    _grid(canvas, size);

    if (w.phase == GPhase.title) return;

    // 화면 흔들림 — 내용물만
    canvas.save();
    if (w.shake > 0.2) {
      final dx = sin(w.time * 91.0) * w.shake;
      final dy = cos(w.time * 73.0) * w.shake;
      canvas.translate(dx, dy);
    }

    // 마나 구슬
    for (final o in w.orbs) {
      _glow(canvas, o.x, o.y, 3.0, P.cyan, core: 0.95);
    }

    // 포효/펄스 (발광 링)
    for (final p in w.pulses) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
          Offset(p.x, p.y),
          p.r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7 * a + 2
            ..color = p.color.withOpacity(0.18 * a));
      canvas.drawCircle(
          Offset(p.x, p.y),
          p.r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = p.color.withOpacity(0.6 * a));
    }

    // 벼락 (연쇄 선)
    for (final l in w.lines) {
      final a = (l.life / l.maxLife).clamp(0.0, 1.0);
      canvas.drawLine(
          Offset(l.x1, l.y1),
          Offset(l.x2, l.y2),
          Paint()
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round
            ..color = l.color.withOpacity(0.18 * a));
      canvas.drawLine(
          Offset(l.x1, l.y1),
          Offset(l.x2, l.y2),
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = l.color.withOpacity(0.95 * a));
    }

    // 적
    for (final e in w.enemies) {
      _enemy(canvas, e);
    }

    // 투사체 (발톱) — 진행 방향 잔상 + 발광
    for (final b in w.bullets) {
      canvas.drawLine(
          Offset(b.x - b.vx * 0.028, b.y - b.vy * 0.028),
          Offset(b.x, b.y),
          Paint()
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = P.gold.withOpacity(0.4));
      _glow(canvas, b.x, b.y, b.radius * 0.7, P.goldSoft);
    }

    // 회전 송곳니 (진화 시 더 많고 크게)
    if (w.fangLv > 0) {
      final cnt = w.fangLv + (w.fangEvo ? 3 : 0);
      final orad = (60 + w.fangLv * 4.0) * (w.fangEvo ? 1.4 : 1.0);
      for (int i = 0; i < cnt; i++) {
        final a = w.orbitAngle + i * 6.2831853 / cnt;
        _glow(canvas, w.px + cos(a) * orad, w.py + sin(a) * orad,
            w.fangEvo ? 8.0 : 6.0, P.cyan, core: 0.95);
      }
    }

    // 파티클 (발광 스파크)
    for (final pt in w.parts) {
      final a = (pt.life / pt.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(pt.x, pt.y), pt.size * a + 0.5,
          Paint()..color = pt.color.withOpacity(a));
      canvas.drawCircle(Offset(pt.x, pt.y), (pt.size * a + 0.5) * 2,
          Paint()..color = pt.color.withOpacity(a * 0.25));
    }

    // 플레이어 (백호 — 네온 골드)
    _player(canvas);
    // 펫 타이니 (졸졸 따라다니며 표정 반응)
    _pet(canvas);

    // 데미지 숫자
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final f in w.floats) {
      final a = (f.life / f.maxLife).clamp(0.0, 1.0);
      tp.text = TextSpan(
        text: f.text,
        style: TextStyle(
          color: f.color.withOpacity(a),
          fontSize: f.size,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y - tp.height / 2));
    }

    canvas.restore();

    // 방향키 — 하단 우측 고정(오른손잡이), 반투명. 노브는 진행 방향 반영. (플레이 중에만)
    if (w.phase != GPhase.playing) return;
    final jx = size.width - 74.0, jy = size.height - 78.0, baseR = 46.0;
    canvas.drawCircle(Offset(jx, jy), baseR,
        Paint()..color = Colors.white.withOpacity(w.jActive ? 0.10 : 0.05));
    canvas.drawCircle(
        Offset(jx, jy),
        baseR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white.withOpacity(w.jActive ? 0.22 : 0.12));
    final kx = jx + w.dirx * (baseR - 18);
    final ky = jy + w.diry * (baseR - 18);
    canvas.drawCircle(Offset(kx, ky), 18,
        Paint()..color = P.gold.withOpacity(w.jActive ? 0.45 : 0.22));
  }

  void _grid(Canvas canvas, Size size) {
    final g = Paint()
      ..color = P.gold.withOpacity(0.025)
      ..strokeWidth = 1;
    const step = 48.0;
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
        base = P.red;
        break;
      case EType.boss:
        base = const Color(0xFFFF4533);
        break;
      case EType.grunt:
        base = const Color(0xFF8A9BB0);
        break;
    }
    // 어두운 코어 + 네온 후광/링 (플레이어보다 어둡게 → 대비로 가독성)
    canvas.drawCircle(Offset(e.x, e.y), e.radius * 1.7, Paint()..color = base.withOpacity(0.10));
    canvas.drawCircle(Offset(e.x, e.y), e.radius, Paint()..color = const Color(0xFF0E0A08));
    canvas.drawCircle(
        Offset(e.x, e.y),
        e.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = base.withOpacity(0.95));
    // 밝은 눈
    final eye = Paint()..color = base;
    canvas.drawCircle(Offset(e.x - e.radius * 0.34, e.y - e.radius * 0.08), e.radius * 0.17, eye);
    canvas.drawCircle(Offset(e.x + e.radius * 0.34, e.y - e.radius * 0.08), e.radius * 0.17, eye);
    // 피격 섬광
    if (e.flash > 0) {
      canvas.drawCircle(Offset(e.x, e.y), e.radius,
          Paint()..color = Colors.white.withOpacity(0.6 * e.flash.clamp(0.0, 1.0)));
    }
    // 보스 체력 링
    if (e.type == EType.boss) {
      final frac = (e.hp / e.maxHp).clamp(0.0, 1.0);
      canvas.drawArc(
          Rect.fromCircle(center: Offset(e.x, e.y), radius: e.radius + 6),
          -1.5708,
          6.2831853 * frac,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..color = P.gold);
    }
  }

  // 펫 타이니 — 작은 아이콘이 플레이어를 따라다니며 표정으로 반응(펫 감성)
  void _pet(Canvas canvas) {
    if (w.phase == GPhase.title) return;
    final t = w.time;
    final bob = sin(t * 4.5) * 2.6;
    final x = w.petX, y = w.petY + bob;
    final hurt = w.contactCdView > 0;
    final happy = w.petHappyT > 0;
    final face = hurt ? '🙀' : (happy ? '😻' : '🐯');
    // 기분에 따라 발광 색/세기
    final gc = hurt ? P.red : (happy ? P.gold : P.muted);
    canvas.drawCircle(Offset(x, y), happy ? 14 : 11,
        Paint()..color = gc.withOpacity(happy ? 0.28 : 0.14));
    final tp = TextPainter(
      text: TextSpan(text: face, style: const TextStyle(fontSize: 18)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  // 플레이어 — 캐릭터별 외형 + 코드 절차 애니메이션(숨쉬기·통통·눈깜빡·꼬리). 귀엽게.
  void _player(Canvas canvas) {
    final hurt = w.contactCdView > 0;
    final id = w.charIndex.clamp(0, kChars.length - 1);
    final ch = kChars[id];
    final col = hurt ? P.red : w.skinColor; // 코스메틱 스킨 색 적용
    final r = w.pr * w.growScale; // 포식할수록 시각적으로 커짐(히트박스는 w.pr 유지)
    final t = w.time;
    final moving = w.dirx != 0 || w.diry != 0;
    // 통통 튀는 숨쉬기/걸음 + squash&stretch
    final bob = sin(t * (moving ? 10.0 : 3.0));
    final cx = w.px;
    final cy = w.py + bob * (moving ? 2.0 : 1.0);
    final sq = 1 + (moving ? bob * 0.10 : bob * 0.045); // 세로 스케일
    final fw = r * 2 / (1 + (sq - 1) * 0.5); // 가로 보정
    final fh = r * 2 * sq;

    // 안광
    canvas.drawCircle(Offset(cx, cy), r * 3.0, Paint()..color = col.withOpacity(0.12));

    // 꼬리 (뒤에서 살랑) — 버팔로는 생략
    if (id != 2) {
      final wag = sin(t * 5) * r * 1.4;
      final tail = Path()
        ..moveTo(cx, cy + r * 0.5)
        ..quadraticBezierTo(cx + wag, cy + r * 1.3, cx + wag * 1.2, cy + r * 0.4);
      canvas.drawPath(
          tail,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..color = col.withOpacity(0.9));
    }

    final earTwitch = sin(t * 2.3) * r * 0.08;
    final earPaint = Paint()..color = col;
    if (id == 1) {
      // 흑표 — 길고 뾰족한 귀
      final ears = Path()
        ..moveTo(cx - r * 0.75, cy - r * 0.4)
        ..lineTo(cx - r * 0.45 + earTwitch, cy - r * 1.55)
        ..lineTo(cx - r * 0.05, cy - r * 0.55)
        ..close()
        ..moveTo(cx + r * 0.75, cy - r * 0.4)
        ..lineTo(cx + r * 0.45 - earTwitch, cy - r * 1.55)
        ..lineTo(cx + r * 0.05, cy - r * 0.55)
        ..close();
      canvas.drawPath(ears, earPaint);
    } else if (id == 2) {
      // 무쇠뿔 — 양옆으로 휜 뿔
      final hp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE8E0D0);
      final lh = Path()
        ..moveTo(cx - r * 0.6, cy - r * 0.5)
        ..quadraticBezierTo(cx - r * 1.5, cy - r * 1.0, cx - r * 1.3, cy - r * 1.6);
      final rh = Path()
        ..moveTo(cx + r * 0.6, cy - r * 0.5)
        ..quadraticBezierTo(cx + r * 1.5, cy - r * 1.0, cx + r * 1.3, cy - r * 1.6);
      canvas.drawPath(lh, hp);
      canvas.drawPath(rh, hp);
    } else {
      // 백호 — 둥근 삼각 귀
      final ears = Path()
        ..moveTo(cx - r * 0.85, cy - r * 0.45)
        ..lineTo(cx - r * 0.45, cy - r * 1.2 - earTwitch)
        ..lineTo(cx - r * 0.05, cy - r * 0.6)
        ..close()
        ..moveTo(cx + r * 0.85, cy - r * 0.45)
        ..lineTo(cx + r * 0.45, cy - r * 1.2 + earTwitch)
        ..lineTo(cx + r * 0.05, cy - r * 0.6)
        ..close();
      canvas.drawPath(ears, earPaint);
    }

    // 얼굴 (squash 타원) — 발광 코어 + 밝은 림
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: fw * 1.7, height: fh * 1.7),
        Paint()..color = col.withOpacity(0.18));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: fw, height: fh),
        Paint()..color = col);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: fw, height: fh),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withOpacity(0.85));

    // 무늬 (백호=줄, 흑표=점)
    if (id == 0) {
      final st = Paint()
        ..color = const Color(0xFF3A2606)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(cx - r * 0.5, cy - r * 0.5), Offset(cx - r * 0.22, cy - r * 0.2), st);
      canvas.drawLine(Offset(cx + r * 0.5, cy - r * 0.5), Offset(cx + r * 0.22, cy - r * 0.2), st);
    } else if (id == 1) {
      final sp = Paint()..color = Colors.black.withOpacity(0.25);
      canvas.drawCircle(Offset(cx - r * 0.45, cy - r * 0.35), r * 0.1, sp);
      canvas.drawCircle(Offset(cx + r * 0.45, cy - r * 0.35), r * 0.1, sp);
    }

    // 볼터치(귀여움)
    final blush = Paint()..color = const Color(0xFFFF8E8E).withOpacity(0.5);
    canvas.drawCircle(Offset(cx - r * 0.55, cy + r * 0.28), r * 0.16, blush);
    canvas.drawCircle(Offset(cx + r * 0.55, cy + r * 0.28), r * 0.16, blush);

    // 눈 (주기적 깜빡임) + 큰 눈망울 + 하이라이트
    final blink = (t % 3.1) < 0.13;
    final ey = cy - r * 0.05;
    final eL = Offset(cx - r * 0.38, ey), eR = Offset(cx + r * 0.38, ey);
    final dark = Paint()..color = const Color(0xFF160F06);
    if (blink) {
      final lid = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = dark.color;
      canvas.drawLine(eL.translate(-r * 0.18, 0), eL.translate(r * 0.18, 0), lid);
      canvas.drawLine(eR.translate(-r * 0.18, 0), eR.translate(r * 0.18, 0), lid);
    } else {
      canvas.drawCircle(eL, r * 0.2, dark);
      canvas.drawCircle(eR, r * 0.2, dark);
      final hi = Paint()..color = Colors.white.withOpacity(0.9);
      canvas.drawCircle(eL.translate(-r * 0.06, -r * 0.07), r * 0.07, hi);
      canvas.drawCircle(eR.translate(-r * 0.06, -r * 0.07), r * 0.07, hi);
    }
    // 코
    canvas.drawCircle(Offset(cx, cy + r * 0.32), r * 0.1, dark);
  }

  @override
  bool shouldRepaint(covariant WorldPainter old) => true;
}
