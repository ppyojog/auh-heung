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

// 카메라 줌 아웃 — 논리 아레나 = 화면 / kZoom (더 넓어 보이게). 1.0=원본, <1=멀리.
const double kZoom = 0.7;

// 세이브 버전 — 값이 바뀌면(=배포마다 갱신) 기존 세이브를 초기화한다(사용자 요청).
const String kSaveVer = 'v2026.06.13-3';

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
// grunt=잡몹 / fast=쾌속 / tank=육중 / swarm=떼거리(약·빠름) /
// splitter=분열(죽으면 둘로) / bomber=자폭(죽을 때 폭발) / shooter=원거리(투사체) / boss=거수
enum EType { grunt, fast, tank, swarm, splitter, bomber, shooter, boss }

class Enemy {
  final int id;
  double x, y;
  double hp, maxHp;
  double speed, dmg, radius;
  EType type;
  double flash = 0; // 피격 섬광
  double atkT = 0; // 원거리 적 사격 쿨다운
  double chill = 0; // 서리(특별스킬) 둔화 잔여시간
  bool elite = false; // 엘리트(정예) — 강하고 보상 확정
  bool dead = false;
  Enemy(this.id, this.x, this.y, this.hp, this.maxHp, this.speed, this.dmg, this.radius, this.type);
}

// 원거리 적이 쏘는 투사체
class EBullet {
  double x, y, vx, vy, dmg, life;
  bool dead = false;
  EBullet(this.x, this.y, this.vx, this.vy, this.dmg, this.life);
}

// 바닥 파워업 픽업 — 줍는 순간 강력한 효과(순간 변수·도파민). 근거: VS 류 '바닥 아이템'.
enum PickType { magnet, bomb, heal }

class Pickup {
  double x, y;
  final PickType type;
  double life; // 일정 시간 뒤 사라짐
  bool dead = false;
  Pickup(this.x, this.y, this.type) : life = 13.0;
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
    '대장님, 곁을 지키겠습니다. 사냥의 시간입니다.',
    '저 타이니, 대장님의 송곳니가 되어 함께하겠습니다.',
  ];
  static const level = [
    '또 강해지셨습니다, 대장님!',
    '이 힘… 대륙이 대장님을 중심으로 돕니다!',
    '발톱이 한층 더 날카로워졌습니다!',
    '점점 더 사나워지시는군요. 역시 제 주인!',
  ];
  static const boss = [
    '보셨습니까! 거수가 대장님 발톱에 찢겼습니다!',
    '저 거대한 놈도 대장님 앞에선 한낱 먹잇감이었군요!',
  ];
  static const ult = [
    '크하핫—! 대륙이 대장님의 포효 앞에 무릎 꿇습니다!!',
    '어흥!! 이것이 진정한 맹수의 울음입니다, 대장님!',
  ];
  static const low = [
    '대장님, 위험합니다 — 잠시 물러서시죠!',
    '피가 보입니다! 부디 조심하십시오, 대장님!',
  ];
  static const streak = [
    '놈들이 줄지어 쓰러집니다, 대장님!',
    '대장님 지나간 자리엔 시체만 쌓입니다!',
  ];
  // 양→호랑이 변신 마일스톤 (USP 강화)
  static const tiger = [
    '대장님… 더는 양이 아니십니다. 호랑이의 눈빛입니다!',
    '털가죽 아래 맹수가 깨어납니다 — 어흥!',
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

// 단일 시작 캐릭터 — '호랑이가 되고 싶은 양'. 순한 양으로 시작해
// 사냥·성장(레벨/포식)할수록 화면 속 모습이 호랑이로 변해간다(USP: 양→호랑이).
const List<Character> kChars = [
  Character('lamb', '호랑이가 되고 싶은 양', '🐑',
      '순한 양. 하지만 사냥할수록 발톱이 돋고, 호랑이로 깨어난다.', P.gold, 'claw'),
];

// 초상화(Portrait) 진급 — 레벨에 따라 양→호랑이 단계가 '짜잔' 공개되고, 단계마다 능력치 상승.
//  prog: 외형(0=양 ~ 1=완전 호랑이). bonus: 그 단계의 '누적 총량'(dmg%·hp·spd%·as%).
class Portrait {
  final String id, name, desc;
  final int reqLevel;
  final double prog;
  final Map<String, double> bonus;
  const Portrait(this.id, this.name, this.desc, this.reqLevel, this.prog, this.bonus);
}

const List<Portrait> kPortraits = [
  Portrait('p0', '순한 양', '아직은 그저 순한 양.', 1, 0.0, {}),
  Portrait('p1', '야성을 깨운 양', '발톱이 돋고 눈빛이 사나워졌다.', 4, 0.30, {'dmg': 10, 'hp': 20}),
  Portrait('p2', '반(半)호랑이', '양의 탈을 절반쯤 벗었다.', 8, 0.55, {'dmg': 20, 'hp': 45, 'spd': 5}),
  Portrait('p3', '호랑이', '마침내 호랑이로 깨어났다.', 13, 0.80, {'dmg': 32, 'hp': 80, 'spd': 8, 'as': 8}),
  Portrait('p4', '백수(百獸)의 왕', '대륙이 두려워하는 폭군.', 20, 1.0, {'dmg': 46, 'hp': 130, 'spd': 12, 'as': 16}),
];

// 특별스킬 — 10레벨마다 1개 선택(중복 불가). 판을 뒤집는 강력한 한 방.
class Special {
  final String id, icon, name, desc;
  const Special(this.id, this.icon, this.name, this.desc);
}

const List<Special> kSpecials = [
  Special('fury', '🐯', '맹수의 격', '모든 공격력 +25%'),
  Special('haste', '⚡', '과부하', '공격 속도 +30%'),
  Special('armor', '🛡', '강철 가죽', '받는 피해 −22%'),
  Special('slow', '🕸', '거미줄 본능', '모든 적 이동속도 −18%'),
  Special('magnet', '🧲', '굶주린 포식', '수집 범위 대폭↑ · 경험치 +30%'),
  Special('regen', '💗', '재생', '매초 체력이 서서히 회복'),
  Special('lifesteal', '🩸', '흡혈', '처치 시 회복량 3배'),
  Special('explode', '💥', '연쇄 폭발', '적 처치 시 주변이 폭발한다'),
  Special('multi', '🌪', '분신 발톱', '발톱 투사체 +1줄기'),
  Special('freeze', '❄', '서리 손길', '맞은 적이 잠시 얼어붙는다'),
];

// 장비(RPG식) — 3슬롯(무기/방어구/장신구) · 레어도 · 스탯 보너스. 영구 보유·장착(메타).
//  획득: 보스 전리품(루트 드랍) + 대장간(송곳니 구매). 가챠·다크패턴 없음(결정형, 윤리적).
//  근거: Death Must Die / Halls of Torment식 슬롯 장비 + 레어도.
enum GearSlot { weapon, armor, trinket }

class Gear {
  final String id, name, icon, desc;
  final GearSlot slot;
  final int rarity; // 0 일반 · 1 희귀 · 2 영웅 · 3 전설
  final int cost; // 송곳니 (대장간 구매가)
  final Map<String, double> stats; // dmg% · as%(공속) · hp · spd% · pick · regen(/s)
  const Gear(this.id, this.name, this.icon, this.slot, this.rarity, this.cost, this.stats, this.desc);
}

const List<Gear> kGear = [
  // 무기 각인 (공격력·공속)
  Gear('w0', '무쇠 발톱', '🗡', GearSlot.weapon, 0, 40, {'dmg': 8}, '공격력 +8%'),
  Gear('w1', '예리한 발톱', '🗡', GearSlot.weapon, 1, 95, {'dmg': 14, 'as': 8}, '공격력 +14% · 공속 +8%'),
  Gear('w2', '폭풍의 발톱', '🗡', GearSlot.weapon, 2, 190, {'dmg': 22, 'as': 14}, '공격력 +22% · 공속 +14%'),
  Gear('w3', '백호의 발톱', '🗡', GearSlot.weapon, 3, 340, {'dmg': 34, 'as': 18}, '전설 · 공격력 +34% · 공속 +18%'),
  // 방어구 (체력·재생)
  Gear('a0', '두꺼운 가죽', '🛡', GearSlot.armor, 0, 35, {'hp': 35}, '최대체력 +35'),
  Gear('a1', '상흔의 가죽', '🛡', GearSlot.armor, 1, 90, {'hp': 60, 'regen': 0.5}, '체력 +60 · 재생 0.5/s'),
  Gear('a2', '강철 비늘', '🛡', GearSlot.armor, 2, 180, {'hp': 95, 'regen': 1.0}, '체력 +95 · 재생 1.0/s'),
  Gear('a3', '불멸의 가죽', '🛡', GearSlot.armor, 3, 320, {'hp': 150, 'regen': 1.6}, '전설 · 체력 +150 · 재생 1.6/s'),
  // 장신구 (이동·수집·잡탕)
  Gear('t0', '바람 부적', '💍', GearSlot.trinket, 0, 35, {'spd': 6, 'pick': 12}, '이동 +6% · 수집 +12'),
  Gear('t1', '탐욕의 부적', '💍', GearSlot.trinket, 1, 90, {'spd': 8, 'pick': 26}, '이동 +8% · 수집 +26'),
  Gear('t2', '사냥꾼의 부적', '💍', GearSlot.trinket, 2, 180, {'spd': 12, 'pick': 30, 'as': 8}, '이동 +12% · 수집 +30 · 공속 +8%'),
  Gear('t3', '폭군의 인장', '💍', GearSlot.trinket, 3, 320, {'spd': 14, 'dmg': 12, 'pick': 30}, '전설 · 이동 +14% · 공격 +12% · 수집 +30'),
];

const List<Color> kRarityCol = [P.parch, P.cyan, P.purple, P.gold];
const List<String> kRarityName = ['일반', '희귀', '영웅', '전설'];

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

enum GPhase { title, playing, levelup, dead, shop, menu, achieve, skins, status, inventory, travel, options, diag, morph }

// 영구 강화(메타 진행) — 죽어도 남는 '송곳니'로 구매. 죽음이 헛되지 않게.
class MetaUp {
  final String id, icon, name, desc;
  final int baseCost, maxLv;
  final double growth;
  const MetaUp(this.id, this.icon, this.name, this.desc, this.baseCost, this.maxLv,
      [this.growth = 1.55]);
}

const List<MetaUp> kMeta = [
  MetaUp('atk', '💪', '맹수의 발톱', '시작 공격력 +5%', 30, 30),
  MetaUp('hp', '❤', '두꺼운 가죽', '시작 체력 +15', 25, 30),
  MetaUp('spd', '🌬', '바람의 다리', '시작 이동속도 +4%', 30, 20),
  MetaUp('pick', '🧲', '굶주린 코', '수집 범위 +8', 25, 20),
  MetaUp('gain', '🦷', '전리품 사냥꾼', '송곳니 획득 +12%', 40, 20),
  MetaUp('crit', '⚡', '치명의 송곳니', '치명타 확률 +2%', 45, 20),
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
  Ach('stage10', '🔥', '불타는 사냥터', '스테이지 10 도달', 50),
  Ach('lv25', '🌟', '초월한 맹수', '레벨 25 도달', 60),
  Ach('surv300', '⌛', '불굴', '5분 생존', 70),
  Ach('stage20', '👑', '대륙의 폭군', '스테이지 20 도달', 100),
  Ach('kill500', '☄', '일기당천', '한 판 500킬', 90),
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

// =============================================================================
//  월드 / 게임 상태 + 업데이트 루프
// =============================================================================
class World {
  final Random rng = Random();
  final Sfx sfx = Sfx();
  GPhase phase = GPhase.title;

  double w = 0, h = 0; // 아레나 크기
  double time = 0; // 생존 시간(초) — 기록·마일스톤·HUD 시계용(0부터)
  // 적 스케일 시간 = 생존시간 + head-start(시작 스테이지까지 자연 도달에 걸리는 시간).
  //  → 높은 스테이지에서 시작하면 "그 스테이지까지 플레이한 상태"와 동일한 강함으로 시작.
  double _headStart = 0;
  double get scaleT => time + _headStart;
  int kills = 0;
  int _mileShown = 0; // 생존 마일스톤 연출 카운터
  // ── 게임필(juice) — 검증된 기법: 크리티컬·히트스톱·콤보·스크린플래시 ──
  int combo = 0; // 연속 처치 콤보(짧은 시간 내 처치 누적)
  double comboT = 0; // 콤보 유지 타이머
  int _comboMileShown = 0; // 콤보 마일스톤 연출
  double _hitStop = 0; // 히트스톱(타격 순간 미세 정지)
  double _hsCd = 0; // 히트스톱 쿨다운(잦은 크리로 슬로모 누적 방지)
  double flashT = 0; // 스크린 플래시 잔여
  Color flashCol = P.gold; // 스크린 플래시 색
  // ── 옵션(설정) — 전역 저장(슬롯 무관). 검증된 표준 옵션 세트 ──
  bool optShake = true; // 화면 흔들림
  bool optFlash = true; // 화면 번쩍임(광과민 접근성)
  bool optDmgNum = true; // 데미지 숫자 표시
  bool optHaptic = true; // 진동(햅틱)
  bool optPerf = false; // 성능 정보(FPS·엔티티 수) 표시 — 진단용
  int joyPos = 1; // 조이스틱 위치 0=좌 1=중앙 2=우
  // 배경 그라데이션 셰이더 캐시(매 프레임 재생성 방지 — 성능)
  Shader? bgShader;
  String bgKey = '';
  // 성능 진단 측정값(ms, 이동평균)
  double updMs = 0, paintMs = 0;

  double get critChance => 0.12 + 0.02 * metaLv('crit'); // 기본 12% + 메타 치명 강화
  double get comboDmg => 1.0 + (combo > 60 ? 60 : combo) * 0.004; // 콤보 공격 보너스(최대 +24%)
  // 히트스톱 발동 — 작은(크리)건 쿨다운 제한, 큰 이벤트(force)는 항상.
  void _hs(double v, {bool force = false}) {
    if (!force && _hsCd > 0) return;
    if (v > _hitStop) _hitStop = v > 0.09 ? 0.09 : v;
    _hsCd = 0.22;
  }

  void _flash(Color c, double v) {
    flashCol = c;
    if (v > flashT) flashT = v;
  }

  // 플레이어
  double px = 0, py = 0;
  double hp = 120, baseMaxHp = 120;
  double baseSpeed = 178; // 이동 빠르게(속도감)
  double pr = 11; // 반지름
  // 광기(어흥!) 궁극기 — 처치로 차오르고, 해방 시 화면 대포효 + 광폭화. 더 자주 터지게 최대치↓.
  double rage = 0, rageMax = 60, berserkT = 0;
  // 펫 타이니 — 플레이어를 졸졸 따라다니며 표정으로 반응 + 짧은 말풍선
  double petX = 0, petY = 0, petHappyT = 0;
  String petLine = '';
  double petLineT = 0, _petSayCd = 0;

  void _petSay(String s) {
    if (_petSayCd > 0) return;
    petLine = s;
    petLineT = 1.6;
    _petSayCd = 3.2;
  }
  // 포식(Devour) — 삼킬수록 회복 + 호랑이가 점점 커짐 (양→호랑이 USP)
  int devour = 0;
  int cheatPending = 0; // [치트] 대기 중인 강제 레벨업(스킬 선택) 횟수
  // 양→호랑이 외형 — 현재 초상화 단계의 prog(이산). 초상화 진급 때 '짜잔' 바뀜.
  double get tigerProg => kPortraits[portraitTier.clamp(0, kPortraits.length - 1)].prog;
  int portraitTier = 0; // 현재 초상화 단계
  double portraitBonus(String k) =>
      kPortraits[portraitTier.clamp(0, kPortraits.length - 1)].bonus[k] ?? 0;
  // 크기는 거의 고정 — 무한정 커지지 않게(성장은 '모핑'으로 표현). 호랑이로 갈수록 아주 약간만 커짐.
  double get growScale => 1.0 + tigerProg * 0.08;
  // 초상화 진급 '짜잔' 컷신 (탭해야 닫힘)
  double morphClock = 0; // 컷신 경과(연출용)
  int morphFromTier = 0; // 직전 단계(능력치 상승분 표시용)
  bool _morphPendingChoice = false; // 컷신 후 강화 선택 열기
  bool _morphPendingSpecial = false; // 그 선택이 특별스킬인지
  // 특별스킬(10레벨마다 1개) — 보유 집합 + 선택중 플래그
  final Set<String> specials = {};
  bool specialChoice = false;
  bool sp(String id) => specials.contains(id);

  // 장비(RPG) — 보유 + 슬롯별 장착(영구). 시작 스테이지 선택값.
  final Set<String> ownedGear = {};
  final Map<GearSlot, String> equipped = {}; // slot → gearId
  int startStage = 1; // 타이틀/사망 화면에서 고른 시작 스테이지
  GPhase statusReturn = GPhase.title; // 상태창에서 돌아갈 화면

  Gear? gearById(String id) {
    for (final g in kGear) {
      if (g.id == id) return g;
    }
    return null;
  }

  // 장착 장비들의 스탯 합 (key: dmg/as/hp/spd/pick/regen)
  double gearStat(String key) {
    double sum = 0;
    for (final id in equipped.values) {
      final g = gearById(id);
      if (g != null) sum += g.stats[key] ?? 0;
    }
    return sum;
  }

  bool buyGear(String id) {
    final g = gearById(id);
    if (g == null || ownedGear.contains(id) || fangs < g.cost) return false;
    fangs -= g.cost;
    ownedGear.add(id);
    equipped[g.slot] ??= id; // 첫 구매면 자동 장착
    _saveMeta();
    return true;
  }

  void equipGear(String id) {
    final g = gearById(id);
    if (g == null || !ownedGear.contains(id)) return;
    equipped[g.slot] = id;
    _saveMeta();
  }

  void unequipSlot(GearSlot s) {
    equipped.remove(s);
    _saveMeta();
  }
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
  // 난이도 = 스테이지 기반. 높을수록 적 강함 + XP·광기 획득 ↑(빠른 성장)
  double diff = 0.78;
  int stage = 1, maxStage = 1; // 현재/최고 도달 스테이지(최고는 슬롯별 영구 저장)
  int pendingStage = 1; // 메뉴에서 고르는 '이동 목표' 스테이지(선택 후 버튼으로 확정)
  double _stageT = 15; // 자동 상승 타이머(초반 빠름 → 점점 길어짐)

  // 스테이지별 난이도 — '상한 없음'. 스테이지가 계속 오르므로 적도 끝없이 강해진다(장수성).
  //  높은 스테이지 = 플레이어가 고른 난이도 = 보상도 비례↑ (VS의 Curse식 자기 난이도 조절).
  double diffForStage(int s) => (0.7 + (s - 1) * 0.08).clamp(0.5, 99.0).toDouble();
  void _applyStageDiff() => diff = diffForStage(stage);
  // 다음 스테이지까지 시간 — 더 짧게(빠른 진행감·잦은 분위기 전환)
  double _stageDuration(int s) => (10.0 + s * 1.8).clamp(10.0, 32.0).toDouble();
  // 스테이지 s까지 자연 도달에 걸리는 누적 시간 → 시작 시 적 스케일 head-start로 사용
  double _stageHeadStart(int s) {
    double t = 0;
    for (int i = 1; i < s; i++) {
      t += _stageDuration(i);
    }
    return t;
  }

  // 타이니 메뉴에서 스테이지 ±조정 — 도달한 최고 스테이지까지만 (클리어한 곳만 선택)
  void setStage(int s) {
    stage = s.clamp(1, maxStage);
    _applyStageDiff();
  }
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
  final List<EBullet> eBullets = []; // 원거리 적 투사체
  final List<Pickup> pickups = []; // 바닥 파워업 픽업
  int freePicks = 0; // 보스 전리품 상자 → 무료 강화 선택권
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
    if (floats.length > 24) floats.removeAt(0); // 상한↓(웹 텍스트 레이아웃 비용 큼)
    floats.add(FloatText(x, y, t, c, size));
  }

  String _pick(List<String> p) => p[rng.nextInt(p.length)];

  // 충신 대사 출력 — 펫 타이니가 직접 말한다(상단 띄우기 X). 레벨업 화면용으로 heraldLine도 보관.
  void _say(String line, {double dur = 3.2, bool force = false, String face = '🐯'}) {
    if (!force && _heraldCd > 0) return;
    heraldLine = line;
    heraldFace = face;
    heraldT = dur;
    _heraldCd = 0.8;
    // 펫 말풍선으로 출력(상단 텍스트 대신). 충신 대사는 잡담 쿨다운 무시하고 표시.
    petLine = line;
    petLineT = dur;
    petHappyT = max(petHappyT, 0.6);
  }


  void openMenu() {
    if (phase == GPhase.playing) {
      pendingStage = stage;
      phase = GPhase.menu;
    }
  }

  // 메뉴에서 STAGE 버튼으로 '이동' 후 재개 (포기하고 마치기 대체)
  void travelToStage(int s) {
    setStage(s);
    pendingStage = stage;
    hp = min(maxHp, hp + maxHp * 0.12); // 사냥터 이동 시 약간의 숨 고르기
    if (phase == GPhase.menu) phase = GPhase.playing;
  }

  void resume() {
    if (phase == GPhase.menu) phase = GPhase.playing;
  }

  // [치트] 내부 테스트 — +10 레벨업을 예약(각 레벨마다 스킬 선택)
  void cheatLevel10() {
    if (phase != GPhase.menu && phase != GPhase.playing) return;
    cheatPending += 10;
    // 풀피 회복 제거 — 순수 레벨업과 동일하게(차이 없게). 레벨업 선택·각성 컷신도 동일 경로.
    phase = GPhase.playing; // 메뉴 닫고 → 레벨업 선택 연쇄 시작
    _say('🐞 치트! 10번 강화를 골라보십시오, 대장님!', force: true, face: '🐞');
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

  // 높은 스테이지로 시작할 때 — '그 스테이지까지 플레이한 만큼'의 시작 빌드를 자동 지급.
  //  (레벨1 맨몸으로 강한 적과 만나 못 이기던 문제 해결. 편의 우선 → 클릭 강요 없이 즉시 강하게.)
  void _grantStartBuild(int st) {
    if (st <= 1) return;
    int picks = ((st - 1) * 1.7).round(); // 스테이지당 약 1.7 강화
    // 생존 보장: 가죽(체력) 먼저 일부 확보
    final hidePre = (picks * 0.2).round();
    hideLv += hidePre;
    picks -= hidePre;
    for (int i = 0; i < picks; i++) {
      final opts = <void Function()>[];
      if (clawLv < 8) {
        opts.add(() => clawLv++);
        opts.add(() => clawLv++); // 시작 무기 가중
      }
      if (fangLv < 6) opts.add(() => fangLv++);
      if (roarLv < 7) opts.add(() => roarLv++);
      if (boltLv < 7) opts.add(() => boltLv++);
      if (spikeLv < 7) opts.add(() => spikeLv++);
      opts.add(() => wildLv++);
      opts.add(() => wildLv++); // 공격력 가중
      opts.add(() => hideLv++);
      opts.add(() => windLv++);
      opts.add(() => hungerLv++);
      opts.add(() => rageLv++);
      opts[rng.nextInt(opts.length)]();
    }
    // 레벨·다음 경험치 재계산 (해당 빌드에 맞는 레벨로)
    level = 1 + ((st - 1) * 1.7).round();
    xpNext = 3;
    for (int l = 1; l < level; l++) {
      xpNext = (xpNext * 1.18 + 2).roundToDouble();
    }
    // 특별스킬: 10레벨마다 1개 자동 부여(중복 없이)
    final sc = level ~/ 10;
    final av = kSpecials.toList()..shuffle(rng);
    for (int i = 0; i < sc && i < av.length; i++) {
      specials.add(av[i].id);
    }
    // 포식 누적 성장도 그 스테이지만큼 미리 확보(고스테이지=그만큼 먹어온 상태)
    devour = (st - 1) * 18;
    // 초상화 단계도 현재 레벨에 맞춰 즉시 적용(컷신 없이 이미 그 모습으로 시작)
    portraitTier = 0;
    for (int i = 0; i < kPortraits.length; i++) {
      if (level >= kPortraits[i].reqLevel) portraitTier = i;
    }
    rage = rageMax * 0.5; // 어흥! 절반 충전 상태로 시작
    hp = maxHp;
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
    _checkSaveVersion(); // 버전 바뀌면 세이브 초기화
    try {
      slot = (int.tryParse(html.window.localStorage['surv_slot'] ?? '1') ?? 1).clamp(1, 3);
    } catch (_) {}
    _loadOpts();
    _loadRecords();
    _loadMeta();
    _checkDaily();
  }

  // 세이브 버전 검사 — kSaveVer가 바뀌면 전 슬롯 세이브 삭제(설정은 유지)
  void _checkSaveVersion() {
    try {
      final v = html.window.localStorage['surv_ver'];
      if (v != kSaveVer) {
        for (int s = 1; s <= 3; s++) {
          html.window.localStorage.remove('surv_rec_$s');
          html.window.localStorage.remove('surv_meta_$s');
        }
        html.window.localStorage.remove('surv_slot');
        html.window.localStorage['surv_ver'] = kSaveVer;
      }
    } catch (_) {}
  }

  // ── 옵션 저장/로드 (전역) ──
  void _loadOpts() {
    try {
      final raw = html.window.localStorage['surv_opts'];
      if (raw == null) return;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      optShake = j['shake'] as bool? ?? true;
      optFlash = j['flash'] as bool? ?? true;
      optDmgNum = j['dmgnum'] as bool? ?? true;
      optHaptic = j['haptic'] as bool? ?? true;
      optPerf = j['perf'] as bool? ?? false;
      sfx.muted = j['mute'] as bool? ?? false;
      joyPos = (j['joy'] as int?) ?? 1;
    } catch (_) {}
  }

  void saveOpts() {
    try {
      html.window.localStorage['surv_opts'] = jsonEncode({
        'shake': optShake,
        'flash': optFlash,
        'dmgnum': optDmgNum,
        'haptic': optHaptic,
        'perf': optPerf,
        'mute': sfx.muted,
        'joy': joyPos,
      });
    } catch (_) {}
  }

  // ── 파생 스탯 (캐릭터 배수 + 광폭화 + 영구강화(meta) + 장비 + 초상화 진급 반영) ──
  double get maxHp =>
      (baseMaxHp + 25 * hideLv + 15 * metaLv('hp') + gearStat('hp') + portraitBonus('hp')) * charHp;
  double get speed =>
      baseSpeed *
      (1 + 0.10 * windLv + 0.04 * metaLv('spd') + 0.01 * gearStat('spd') + 0.01 * portraitBonus('spd')) *
      charSpeed *
      (berserkT > 0 ? 1.18 : 1.0);
  double get pickupRange =>
      72 + 16.0 * hungerLv + 8 * metaLv('pick') + gearStat('pick') + (sp('magnet') ? 80 : 0);
  // 포식(Devour) 누적 성장 — 먹을수록(처치할수록) 연속적으로 강해진다(양→호랑이 핵심 파워).
  //  레벨/선택은 '빌드 방향', 포식은 '꾸준한 누적 파워'로 역할 분리(밸런스 스윙↓).
  // 포식 누적 — 무한 폭주 방지로 상한(공격 최대 +120%, 공속 +50%). 그 뒤는 빌드·장비·환생으로 성장.
  double get devourAtk => (0.0025 * devour).clamp(0.0, 1.2);
  double get devourAs => (0.0012 * devour).clamp(0.0, 0.5);
  double get dmgMult =>
      (1 + 0.12 * wildLv + 0.05 * metaLv('atk') + 0.01 * gearStat('dmg') + 0.01 * portraitBonus('dmg') + devourAtk) *
      charDmg *
      comboDmg *
      (berserkT > 0 ? 1.35 : 1.0) *
      (sp('fury') ? 1.25 : 1.0);
  double get fireMult =>
      1.25 * // 기본 공속 상향(속도감·정신없는 탄막)
      (1 + 0.10 * rageLv + 0.01 * gearStat('as') + 0.01 * portraitBonus('as') + devourAs) *
      (berserkT > 0 ? 1.6 : 1.0) *
      (sp('haste') ? 1.3 : 1.0);
  double get armorMult => sp('armor') ? 0.78 : 1.0; // 받는 피해 배수
  // 경험치 배수 — 스테이지 보너스 완화(누적 성장이 고스테이지 파워를 담당하므로 레벨 폭주 방지)
  double get xpMult => 1.0 + (stage - 1) * 0.1;
  bool get rageReady => rage >= rageMax;

  void toggleMute() => sfx.muted = !sfx.muted;

  void startGame({int? atStage}) {
    sfx.init(); // 사용자 탭(시작 버튼) 직후 → 오디오 정책 통과
    phase = GPhase.playing;
    time = 0;
    kills = 0;
    _mileShown = 0;
    level = 1;
    xp = 0;
    xpNext = 3;
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
    specials.clear();
    specialChoice = false;
    portraitTier = 0;
    morphClock = 0;
    morphFromTier = 0;
    _morphPendingChoice = false;
    _morphPendingSpecial = false;
    clawT = 0;
    roarT = 0;
    boltT = 0;
    spikeT = 0;
    spawnT = 1.4; // 첫 몇 초 숨 돌릴 여유
    bossT = 60; // 첫 보스(전리품 상자)는 좀 더 일찍 → 초반 보상 스파이크
    orbitAngle = 0;
    enemies.clear();
    bullets.clear();
    eBullets.clear();
    pickups.clear();
    freePicks = 0;
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
    petLine = '';
    petLineT = 0;
    _petSayCd = 0;
    devour = 0;
    cheatPending = 0;
    runBoss = 0;
    pendingAch.clear();
    heraldLine = '';
    heraldT = 0;
    _heraldCd = 0;
    _lowCd = 0;
    _streakKillMark = 0;
    combo = 0;
    comboT = 0;
    _comboMileShown = 0;
    _hitStop = 0;
    _hsCd = 0;
    flashT = 0;
    stage = (atStage ?? startStage).clamp(1, maxStage); // 선택한 시작 스테이지에서 출발
    pendingStage = stage;
    startStage = stage;
    _headStart = _stageHeadStart(stage); // 높은 스테이지 시작 = 그만큼 적 스케일 당겨오기
    _stageT = _stageDuration(stage);
    _applyStageDiff();
    _grantStartBuild(stage); // 높은 스테이지면 그만큼의 시작 빌드(무기/패시브/레벨/특별스킬) 자동 지급
    jActive = false;
    dirx = diry = 0;
    if (stage > 1) {
      _say('STAGE $stage의 맹수로 깨어나셨습니다, 대장님 — 이미 강대하십니다!', force: true, face: '😼');
    } else {
      _say(_pick(Tiny.greet), force: true, face: '🐯');
    }
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
    _flash(P.gold, 0.7);
    _hs(0.07, force: true);
    _float(px, py - 30, '어 흥 !!', P.gold, 30);
    _say(_pick(Tiny.ult), force: true, face: '🔥');
    _shakeAdd(18);
    _hapticBig = true;
    sfx.play('boss');
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
    // 초상화 진급 '짜잔' 컷신 — 멈춰서 연출. 탭(dismissMorph)해야만 닫힌다.
    if (phase == GPhase.morph) {
      if (dt > 0.05) dt = 0.05;
      morphClock += dt;
      return;
    }
    if (phase != GPhase.playing) return;
    if (w <= 0 || h <= 0) return;
    if (dt > 0.05) dt = 0.05;
    // 히트스톱 — 타격 순간 월드를 미세하게 정지(타격감). 쿨다운/잔여는 실시간으로 소진.
    if (_hsCd > 0) _hsCd -= dt;
    if (_hitStop > 0) {
      _hitStop -= dt;
      dt *= 0.12;
    }
    // 콤보 유지/소멸 + 스크린 플래시 소멸
    if (comboT > 0) {
      comboT -= dt;
      if (comboT <= 0) {
        combo = 0;
        _comboMileShown = 0;
      }
    }
    if (flashT > 0) flashT = max(0, flashT - dt * 3.2);
    time += dt;
    if (berserkT > 0) berserkT = max(0, berserkT - dt);
    // 펫 타이니 — 이동 방향의 '뒤'를 360° 따라다님(움직이는 쪽 반대편으로 자동 조정)
    if (petHappyT > 0) petHappyT = max(0, petHappyT - dt);
    if (petLineT > 0) petLineT -= dt;
    if (_petSayCd > 0) _petSayCd -= dt;
    // 재생 — 특별스킬(최대체력 1.2%/s) + 장비 regen(고정/s)
    if (hp < maxHp) {
      double rps = sp('regen') ? maxHp * 0.012 : 0;
      rps += gearStat('regen');
      if (rps > 0) hp = min(maxHp, hp + rps * dt);
    }
    final moving0 = dirx != 0 || diry != 0;
    final tpx = moving0 ? px - dirx * 28 : px - 22;
    final tpy = moving0 ? py - diry * 28 : py - 24;
    final k = (dt * 7).clamp(0.0, 1.0);
    petX += (tpx - petX) * k;
    petY += (tpy - petY) * k;
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
      _petSay('조심하세요!');
      _say(_pick(Tiny.low), face: '😿');
    }
    // 학살 연쇄
    if (kills - _streakKillMark >= 30) {
      _streakKillMark = kills;
      _petSay('크항—!');
      _say(_pick(Tiny.streak), face: '😼');
    }
    // 스테이지 자동 상승 — 초반은 빠르게(짧은 간격), 갈수록 천천히. 한 칸의 난이도 간극은 완만.
    _stageT -= dt;
    if (_stageT <= 0) {
      stage += 1;
      _stageT = _stageDuration(stage);
      if (stage > maxStage) {
        maxStage = stage;
        _saveMeta();
      }
      _applyStageDiff();
      _say('스테이지 $stage 진입! 더 사나운 놈들이 몰려옵니다!', force: true, face: '😼');
      _shakeAdd(6);
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
    _updateEBullets(dt);
    _updatePickups(dt);
    _updateOrbs(dt);
    _updateFx(dt);

    // 사망
    if (hp <= 0) {
      hp = 0;
      _onDeath();
      return;
    }
    // 레벨업 (cheatPending이 있으면 강제 레벨업 → 정상 선택 흐름)
    if (xp >= xpNext || cheatPending > 0) {
      if (cheatPending > 0) {
        cheatPending -= 1;
      } else {
        xp -= xpNext;
      }
      level += 1;
      xpNext = (xpNext * 1.18 + 2).roundToDouble();
      _hapticBig = true;
      _shakeAdd(9);
      petHappyT = 1.6; // 펫이 신남
      _petSay('오— 강해졌다!');
      sfx.play('level');
      pulses.add(Pulse(px, py, 120, 0.5, P.gold));
      _flash(P.gold, 0.35);
      final wantSpecial = level % 10 == 0 && specials.length < kSpecials.length;
      // 초상화 진급 — 다음 단계 요구레벨 도달 시 '짜잔' 컷신(레벨 기준 → 치트·자연 동일). 능력치도 상승.
      if (portraitTier + 1 < kPortraits.length && level >= kPortraits[portraitTier + 1].reqLevel) {
        final from = portraitTier;
        portraitTier += 1;
        _morphPendingSpecial = wantSpecial;
        _triggerMorph(from);
        return;
      }
      _say(_pick(Tiny.level), force: true, face: '😺');
      if (wantSpecial) {
        _openSpecial();
      } else {
        _openLevelUp();
      }
      return;
    }
    // 보스 전리품 상자 → 무료 강화 선택(레벨업과 같은 화면 재사용, 도파민 스파이크)
    if (freePicks > 0 && phase == GPhase.playing) {
      freePicks -= 1;
      _hapticBig = true;
      _shakeAdd(6);
      pulses.add(Pulse(px, py, 130, 0.5, P.gold));
      sfx.play('level');
      _say('전리품 상자! 원하는 힘을 고르십시오, 대장님!', force: true, face: '🎁');
      _openLevelUp();
    }
  }

  // ── 스폰 ──
  void _spawn(double dt) {
    bossT -= dt;
    if (bossT <= 0) {
      bossT = max(40.0, 90.0 - stage * 1.6); // 스테이지 오를수록 보스 더 자주(엔드 압박)
      _spawnBoss();
    }
    spawnT -= dt;
    if (spawnT > 0) return;
    // 속도감 — 자주·많이(화면 가득). 단 성능 위해 동시 수 상한 보수적으로(개체는 약해 즉사).
    final interval = max(0.34, 1.7 - scaleT * 0.012).toDouble();
    spawnT = interval;
    if (enemies.length > 96) return;
    final count = 1 + (scaleT ~/ 44);
    for (int i = 0; i < count; i++) {
      if (enemies.length > 96) break;
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
    // 타입 결정 — 스테이지가 오를수록 새 적 해금(다양성). 초반은 잡몹·떼거리 위주.
    EType t = EType.grunt;
    final roll = rng.nextDouble();
    if (stage >= 5 && roll < 0.10) {
      t = EType.bomber; // 자폭
    } else if (stage >= 4 && roll < 0.22) {
      t = EType.shooter; // 원거리
    } else if (stage >= 3 && roll < 0.34) {
      t = EType.splitter; // 분열
    } else if (scaleT > 70 && roll < 0.46) {
      t = EType.tank;
    } else if (scaleT > 26 && roll < 0.62) {
      t = EType.fast;
    } else if (stage >= 2 && roll < 0.80) {
      t = EType.swarm; // 떼거리
    }
    // 적 체력 — scaleT·diff로 끝없이 증가(고스테이지일수록 탱키 → 범위기술이 즉삭 못함, 지속 긴장).
    final base = (7 + scaleT * 0.5) * diff;
    Enemy e;
    if (t == EType.fast) {
      e = Enemy(_eid++, x, y, base * 0.62, base * 0.62, 72 + scaleT * 0.17, (3.2 + scaleT * 0.024) * diff, 9, t);
    } else if (t == EType.swarm) {
      e = Enemy(_eid++, x, y, base * 0.4, base * 0.4, 90 + scaleT * 0.2, (2.4 + scaleT * 0.016) * diff, 7, t);
    } else if (t == EType.tank) {
      e = Enemy(_eid++, x, y, base * 2.8, base * 2.8, 30 + scaleT * 0.05, (7 + scaleT * 0.04) * diff, 18, t);
    } else if (t == EType.splitter) {
      e = Enemy(_eid++, x, y, base * 1.25, base * 1.25, 40 + scaleT * 0.08, (4 + scaleT * 0.024) * diff, 14, t);
    } else if (t == EType.bomber) {
      e = Enemy(_eid++, x, y, base * 0.85, base * 0.85, 54 + scaleT * 0.12, (3.2 + scaleT * 0.016) * diff, 13, t);
    } else if (t == EType.shooter) {
      final se = Enemy(_eid++, x, y, base * 0.75, base * 0.75, 26 + scaleT * 0.05, (3.2 + scaleT * 0.016) * diff, 11, t);
      se.atkT = 0.8 + rng.nextDouble() * 1.6; // 첫 사격 분산
      e = se;
    } else {
      e = Enemy(_eid++, x, y, base, base, 44 + scaleT * 0.12, (3.6 + scaleT * 0.024) * diff, 11, t);
    }
    // 엘리트(정예) — 스테이지 오를수록 더 자주. 강하지만 처치 시 확정 보상(우선 타겟·긴장).
    if (t != EType.swarm && scaleT > 35 && rng.nextDouble() < (0.04 + stage * 0.004).clamp(0.04, 0.2)) {
      e.elite = true;
      e.hp *= 3.2;
      e.maxHp *= 3.2;
      e.radius *= 1.35;
      e.dmg *= 1.25;
    }
    enemies.add(e);
  }

  void _spawnBoss() {
    final x = px + (rng.nextBool() ? 1 : -1) * w * 0.5;
    final y = py + (rng.nextBool() ? 1 : -1) * h * 0.4;
    final base = (240 + scaleT * 6) * diff;
    enemies.add(Enemy(_eid++, x.clamp(0.0, w), y.clamp(0.0, h), base, base, 40, (22 + scaleT * 0.08) * diff, 30, EType.boss));
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
      if ((target != null || clawEvo) && bullets.length < 220) {
        final dmg = (9 + clawLv * 4) * dmgMult * (clawEvo ? 1.7 : 1.0);
        final pierce = clawEvo ? 3 : (clawLv >= 5 ? 1 : 0);
        if (clawEvo) {
          for (int i = 0; i < 16; i++) {
            final a = orbitAngle * 0.4 + i * 6.2831853 / 16;
            bullets.add(Bullet(px, py, cos(a) * 360, sin(a) * 360, dmg, 6, 1.5, pierce));
          }
        } else {
          final n = 1 +
              (clawLv >= 2 ? 1 : 0) +
              (clawLv >= 4 ? 1 : 0) +
              (clawLv >= 6 ? 1 : 0) +
              (sp('multi') ? 1 : 0);
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
            _dealHit(nxt, dmg, P.cyan, 12);
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
        final dmg = (8 + spikeLv * 6) * dmgMult;
        final ox = px + (rng.nextDouble() - 0.5) * 160;
        final oy = py + (rng.nextDouble() - 0.5) * 160;
        for (final e in enemies) {
          final rr = radius + e.radius;
          if ((e.x - ox) * (e.x - ox) + (e.y - oy) * (e.y - oy) <= rr * rr) {
            _dealHit(e, dmg, P.green, 12);
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
        final dmg = (8 + roarLv * 7) * dmgMult * (roarEvo ? 2.2 : 1.0);
        final push = roarEvo ? 30.0 : 14.0;
        for (final e in enemies) {
          final d = sqrt((e.x - px) * (e.x - px) + (e.y - py) * (e.y - py));
          if (d <= radius + e.radius) {
            _dealHit(e, dmg, P.gold, 12);
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
    final slowMul = sp('slow') ? 0.82 : 1.0;
    for (final e in enemies) {
      final dx = px - e.x, dy = py - e.y;
      final d = sqrt(dx * dx + dy * dy);
      double sm = slowMul;
      if (e.chill > 0) {
        e.chill -= dt;
        sm *= 0.4; // 서리 둔화
      }
      if (d > 0.1) {
        e.x += dx / d * e.speed * sm * dt;
        e.y += dy / d * e.speed * sm * dt;
      }
      if (e.flash > 0) e.flash -= dt * 4;
      // 원거리 적 — 주기적으로 플레이어를 향해 투사체 발사
      if (e.type == EType.shooter) {
        e.atkT -= dt;
        if (e.atkT <= 0) {
          e.atkT = 2.2;
          if (d > 1 && eBullets.length < 80) {
            const pspd = 165.0;
            eBullets.add(EBullet(e.x, e.y, dx / d * pspd, dy / d * pspd, e.dmg * 1.4 + 3, 4.0));
          }
        }
      }
    }
  }

  // 원거리 적 투사체 — 이동 + 플레이어 충돌
  void _updateEBullets(double dt) {
    for (final b in eBullets) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.life -= dt;
      if (b.life <= 0 || b.x < -30 || b.x > w + 30 || b.y < -30 || b.y > h + 30) {
        b.dead = true;
        continue;
      }
      final rr = pr + 5;
      if ((b.x - px) * (b.x - px) + (b.y - py) * (b.y - py) <= rr * rr) {
        hp -= b.dmg * armorMult;
        b.dead = true;
        contactCdView = 0.12;
        _hapticHit = true;
        _shakeAdd(3);
      }
    }
    eBullets.removeWhere((b) => b.dead);
  }

  // 바닥 파워업 — 가까우면 끌려오고, 닿으면 발동(자석/폭탄/회복)
  void _updatePickups(double dt) {
    final grab = pr + 16;
    for (final pk in pickups) {
      pk.life -= dt;
      if (pk.life <= 0) {
        pk.dead = true;
        continue;
      }
      final dx = px - pk.x, dy = py - pk.y;
      final d2 = dx * dx + dy * dy;
      if (d2 < 150 * 150) {
        final d = sqrt(d2);
        if (d > 0.1) {
          final pull = 90 + (150 - d) * 2;
          pk.x += dx / d * pull * dt;
          pk.y += dy / d * pull * dt;
        }
      }
      if (d2 < grab * grab) {
        pk.dead = true;
        _collectPickup(pk.type);
      }
    }
    pickups.removeWhere((p) => p.dead);
  }

  void _collectPickup(PickType t) {
    _hapticBig = true;
    if (t == PickType.magnet) {
      // 화면의 모든 구슬 즉시 흡수 (젬 폭발 = 도파민)
      double gained = 0;
      for (final o in orbs) {
        gained += o.value;
        parts.add(Particle(o.x, o.y, (px - o.x) * 2, (py - o.y) * 2, 0.25, 2, P.cyan));
      }
      xp += gained * xpMult * (sp('magnet') ? 1.3 : 1.0);
      orbs.clear();
      _float(px, py - 28, '🧲 전부 흡수!', P.cyan, 16);
      pulses.add(Pulse(px, py, 160, 0.4, P.cyan));
      sfx.play('pick');
    } else if (t == PickType.bomb) {
      // 화면 전체 폭발 (약한 적 청소)
      final dmg = 50 + level * 9.0;
      for (final e in enemies) {
        _hurt(e, dmg);
      }
      pulses.add(Pulse(px, py, max(w, h), 0.5, P.red));
      pulses.add(Pulse(px, py, max(w, h) * 0.55, 0.4, const Color(0xFFE8702E)));
      _float(px, py - 28, '💥 폭발!', P.red, 18);
      _shakeAdd(12);
      sfx.play('boss');
    } else {
      // 회복
      hp = min(maxHp, hp + maxHp * 0.32);
      _float(px, py - 28, '❤ 회복!', P.green, 16);
      pulses.add(Pulse(px, py, 110, 0.4, P.green));
      sfx.play('pick');
    }
  }

  // 보스 전리품 — 미보유 장비 중 1개를 확률 드랍(루트 감성). 낮은 레어도일수록 잘 나옴.
  void _dropGearLoot() {
    final pool = kGear.where((g) => !ownedGear.contains(g.id)).toList();
    if (pool.isEmpty) return;
    if (rng.nextDouble() > 0.6) return; // 60%만 드랍
    final weights = <double>[];
    double tot = 0;
    for (final g in pool) {
      final wgt = 1.0 / (1 + g.rarity * 1.6);
      weights.add(wgt);
      tot += wgt;
    }
    double r = rng.nextDouble() * tot;
    Gear pick = pool.first;
    for (int i = 0; i < pool.length; i++) {
      r -= weights[i];
      if (r <= 0) {
        pick = pool[i];
        break;
      }
    }
    ownedGear.add(pick.id);
    equipped[pick.slot] ??= pick.id;
    _saveMeta();
    _float(px, py - 42, '전리품! ${pick.name}', kRarityCol[pick.rarity], 16);
    _say('전리품입니다, 대장님 — ${pick.name}! 장비창에서 확인하시죠.', force: true, face: '🎁');
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
          _dealHit(e, b.dmg, P.goldSoft, 13);
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
      final fdps = (20 + fangLv * 12) * dmgMult * (fangEvo ? 1.9 : 1.0);
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
            if (rng.nextDouble() < 0.04) {
              _float(e.x, e.y - e.radius - 4, fdps.round().toString(), P.cyan, 11);
            }
          }
        }
      }
    }

    // 적 vs 플레이어 (접촉 지속 데미지) — 강철 가죽(armor) 반영
    contactCdView = max(0.0, contactCdView - dt);
    for (final e in enemies) {
      final rr = e.radius + pr;
      if ((e.x - px) * (e.x - px) + (e.y - py) * (e.y - py) <= rr * rr) {
        hp -= e.dmg * dt * armorMult; // 접촉 피해(고스테이지일수록 diff로 커져 위협)
        contactCdView = 0.12;
        _hapticHit = true;
        _shakeAdd(3);
      }
    }

    // 죽은 적 처리 → 구슬/파티클 (반복 중 enemies에 직접 추가 금지 → newborn에 모았다가 뒤에서 add)
    final newborn = <Enemy>[];
    for (final e in enemies) {
      if (e.hp <= 0 && !e.dead) {
        e.dead = true;
        kills += 1;
        petHappyT = 1.0; // 펫이 기뻐함
        // [포식] 삼켜서 회복 + 성장
        devour += 1;
        // 콤보 — 연속 처치 누적(짧은 유지창). 높을수록 공격 보너스 + 연출 고조.
        combo += 1;
        comboT = 2.4;
        if (combo >= 10 && combo - _comboMileShown >= 10) {
          _comboMileShown = combo;
          sfx.play('level');
          _hs(0.03);
        }
        // 엘리트 처치 — 확정 보상(파워업 픽업 + 송곳니) + 큰 연출
        if (e.elite) {
          if (pickups.length < 8) {
            pickups.add(Pickup(e.x.clamp(16.0, w - 16), e.y.clamp(16.0, h - 16),
                PickType.values[rng.nextInt(PickType.values.length)]));
          }
          fangs += 8;
          runFangs += 8;
          devour += 6;
          _float(e.x, e.y - e.radius - 8, 'ELITE 격파! +🦷8', P.gold, 17);
          _flash(P.gold, 0.5);
          _hs(0.06, force: true);
          _shakeAdd(8);
          _hapticBig = true;
        }
        double heal = e.type == EType.boss
            ? 12.0
            : (e.type == EType.tank ? 2.5 : (e.type == EType.fast ? 0.4 : 0.6));
        if (sp('lifesteal')) heal *= 3; // 흡혈
        if (hp < maxHp) {
          hp = min(maxHp, hp + heal);
          if (heal >= 2.5) _float(e.x, e.y - e.radius, '+${heal.round()}♥', P.green, 13);
        }
        // 분열 — 죽으면 작은 떼거리 둘로 갈라짐
        if (e.type == EType.splitter) {
          final cb = (7 + scaleT * 0.5) * diff * 0.45;
          for (int s = 0; s < 2; s++) {
            final ang = rng.nextDouble() * 6.2831853;
            newborn.add(Enemy(_eid++, e.x + cos(ang) * 14, e.y + sin(ang) * 14, cb, cb,
                88 + scaleT * 0.12, (3.5 + scaleT * 0.02) * diff, 7, EType.swarm));
          }
        }
        // 자폭 — 죽을 때 주변 폭발(플레이어 피해 + 연출)
        if (e.type == EType.bomber) {
          const er = 72.0;
          final ed = (16 + scaleT * 0.1) * diff;
          final pd = sqrt((px - e.x) * (px - e.x) + (py - e.y) * (py - e.y));
          if (pd < er + pr) hp -= ed * armorMult;
          pulses.add(Pulse(e.x, e.y, er, 0.4, P.red));
          _float(e.x, e.y - e.radius, '폭발!', P.red, 16);
          _shakeAdd(6);
        }
        // 연쇄 폭발(특별스킬) — 처치 시 주변 적에게 피해
        if (sp('explode')) {
          const xr = 58.0;
          final xd = (12 + level * 2.0) * dmgMult;
          for (final o in enemies) {
            if (o.dead || o.id == e.id) continue;
            if ((o.x - e.x) * (o.x - e.x) + (o.y - e.y) * (o.y - e.y) <= xr * xr) {
              _hurt(o, xd);
            }
          }
          pulses.add(Pulse(e.x, e.y, xr, 0.3, P.gold));
        }
        rage = min(rageMax, rage + (e.type == EType.boss ? 14 : (e.type == EType.tank ? 3 : 1)) * diff);
        if (e.type == EType.boss) {
          runBoss += 1;
          freePicks += 1; // 전리품 상자 → 무료 강화 선택
          _float(e.x, e.y - e.radius, 'BOSS 격파! 🎁', P.gold, 18);
          _petSay('해냈다!');
          _say(_pick(Tiny.boss), force: true, face: '😼');
          _shakeAdd(10);
          _hapticBig = true;
          _flash(P.blood, 0.6);
          _hs(0.08, force: true);
          _dropGearLoot(); // 보스 전리품 → 장비 루트(미보유 중 1개) 획득 가능
        }
        // 화면(아레나) 안에만 떨구기 — 가장자리 밖에서 죽어도 구슬은 안쪽으로 클램프(못 줍는 일 방지)
        final drops = e.type == EType.boss ? 14 : (e.type == EType.tank ? 3 : 1);
        for (int i = 0; i < drops; i++) {
          final ox = (e.x + (rng.nextDouble() - 0.5) * 24).clamp(12.0, w - 12);
          final oy = (e.y + (rng.nextDouble() - 0.5) * 24).clamp(12.0, h - 12);
          orbs.add(Orb(ox, oy, e.type == EType.boss ? 4.0 : 1.0));
        }
        // 바닥 파워업 가끔 드랍(탱크·분열은 확률↑) — 순간 변수·도파민. 역시 화면 안으로.
        final pdrop = e.type == EType.boss
            ? 0.0
            : (e.type == EType.tank ? 0.16 : (e.type == EType.splitter ? 0.06 : 0.022));
        if (pickups.length < 6 && rng.nextDouble() < pdrop) {
          pickups.add(Pickup(e.x.clamp(16.0, w - 16), e.y.clamp(16.0, h - 16),
              PickType.values[rng.nextInt(PickType.values.length)]));
        }
        final col = e.type == EType.fast
            ? P.purple
            : (e.type == EType.tank
                ? P.blood
                : (e.type == EType.bomber
                    ? const Color(0xFFE8702E)
                    : (e.type == EType.splitter ? P.green : P.muted)));
        // 파티클 — 성능 위해 수 축소 + 총량 상한(과밀 시 생략)
        if (parts.length < 160) {
          for (int i = 0; i < (e.type == EType.boss ? 12 : 4); i++) {
            final a = rng.nextDouble() * 6.2831853;
            final spd = 40 + rng.nextDouble() * 120;
            parts.add(Particle(e.x, e.y, cos(a) * spd, sin(a) * spd, 0.35 + rng.nextDouble() * 0.25,
                2 + rng.nextDouble() * 3, col));
          }
        }
      }
    }
    enemies.removeWhere((e) => e.dead);
    if (newborn.isNotEmpty) enemies.addAll(newborn);
  }

  void _hurt(Enemy e, double dmg) {
    e.hp -= dmg;
    e.flash = 1;
    if (sp('freeze') && e.type != EType.boss) e.chill = 1.2; // 서리 손길
  }

  // 단발 타격 — 크리티컬 판정 + 데미지 숫자 연출(크리=금색 큰 숫자 + 히트스톱). 검증된 게임필.
  void _dealHit(Enemy e, double dmg, Color col, double size) {
    final crit = rng.nextDouble() < critChance;
    final d = crit ? dmg * 2.0 : dmg;
    _hurt(e, d);
    // 데미지 숫자는 웹에서 비싸므로 크리만 항상, 일반 타격은 일부만 표시(렉 방지)
    if (crit) {
      _float(e.x, e.y - e.radius - 6, '${d.round()}!', P.gold, size + 7);
      _hs(0.045); // 크리 순간 미세 정지
    } else if (rng.nextDouble() < 0.3) {
      _float(e.x, e.y - e.radius - 4, d.round().toString(), col, size);
    }
  }

  // ── 구슬 ──
  void _updateOrbs(double dt) {
    // 구슬 과밀 방지(성능) — 너무 많으면 오래된 것 자동 흡수
    if (orbs.length > 50) {
      final excess = orbs.length - 50;
      for (int i = 0; i < excess; i++) {
        xp += orbs[i].value * xpMult;
      }
      orbs.removeRange(0, excess);
    }
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
          xp += o.value * xpMult * (sp('magnet') ? 1.3 : 1.0); // 스테이지↑일수록 XP↑ · 자성 보정
          o.dead = true;
          sfx.play('pick', gapMs: 35);
        }
      }
    }
    orbs.removeWhere((o) => o.dead);
  }

  void _updateFx(double dt) {
    // 펄스 과밀 방지(성능) — 폭발·포효·처치 등으로 누적되면 오래된 것부터 제거
    if (pulses.length > 40) pulses.removeRange(0, pulses.length - 40);
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

  // 초상화 진급 '짜잔' 컷신 시작 — 화면을 멈추고 새 초상화 공개(탭해야 닫힘)
  void _triggerMorph(int fromTier) {
    morphFromTier = fromTier;
    morphClock = 0;
    _morphPendingChoice = true;
    phase = GPhase.morph;
    _hapticBig = true;
    _shakeAdd(10);
    sfx.play('boss'); // 묵직한 각성음
  }

  // 컷신 닫기(탭) — 연출 0.4초 지난 뒤에만(실수 방지). 닫으면 대기 중 강화 선택 열림.
  void dismissMorph() {
    if (phase != GPhase.morph || morphClock < 0.4) return;
    if (_morphPendingChoice) {
      _morphPendingChoice = false;
      if (_morphPendingSpecial) {
        _openSpecial();
      } else {
        _openLevelUp();
      }
    } else {
      phase = GPhase.playing;
    }
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

  // 10레벨마다 — 특별스킬 3택(보유하지 않은 것 중에서). 즉시 효과(getter로 반영).
  void _openSpecial() {
    phase = GPhase.levelup;
    specialChoice = true;
    final avail = kSpecials.where((s) => !specials.contains(s.id)).toList()..shuffle(rng);
    final out = <Upgrade>[];
    for (final s in avail.take(3)) {
      out.add(Upgrade(s.icon, s.name, s.desc, () {
        specials.add(s.id);
        if (s.id == 'regen' || s.id == 'lifesteal') hp = min(maxHp, hp + maxHp * 0.15);
      }));
    }
    choices = out;
  }

  void pick(Upgrade u) {
    u.apply();
    choices = [];
    specialChoice = false;
    phase = GPhase.playing;
  }

  void _onDeath() {
    phase = GPhase.dead;
    _hapticBig = true;
    startStage = stage; // 사용자 선택: 죽은 스테이지에서 바로 재시작(사망 화면서 변경 가능)
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
    if (stage >= 10) _grantAch('stage10', 50);
    if (level >= 25) _grantAch('lv25', 60);
    if (time >= 300) _grantAch('surv300', 70);
    if (stage >= 20) _grantAch('stage20', 100);
    if (kills >= 500) _grantAch('kill500', 90);
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
    maxStage = 1;
    bestTime = 0;
    bestKills = 0;
    ownedGear.clear();
    equipped.clear();
    startStage = 1;
    _loadRecords();
    _loadMeta();
    _checkDaily();
  }

  // 세이브 삭제 — 해당 슬롯의 기록·메타를 영구 제거. 현재 슬롯이면 초기화 상태로 리로드.
  void deleteSlot(int s) {
    try {
      html.window.localStorage.remove('surv_rec_$s');
      html.window.localStorage.remove('surv_meta_$s');
    } catch (_) {}
    if (s == slot) selectSlot(s); // 빈 슬롯으로 다시 로드(전부 초기화)
  }

  // 데일리 보너스 — 하루 첫 접속 시 송곳니 +30 (리텐션, 비강제)
  //  ※ 기존 세이브가 있는 슬롯에만 지급. 빈 슬롯을 누를 때 보너스가 생기거나
  //    슬롯이 멋대로 만들어지는 현상 방지(+ 삭제→재선택 악용 차단).
  void _checkDaily() {
    try {
      bool hasSave = false;
      try {
        hasSave = html.window.localStorage[_metaKey] != null;
      } catch (_) {}
      if (!hasSave) return; // 빈 슬롯이면 아무것도 하지 않음
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
      maxStage = (j['maxst'] as int?) ?? 1;
      ownedGear.addAll(((j['gear'] as List?) ?? []).map((e) => e as String));
      final eq = (j['equip'] as Map?) ?? {};
      eq.forEach((k, v) {
        final si = int.tryParse(k.toString());
        if (si != null && si >= 0 && si < GearSlot.values.length && v is String) {
          equipped[GearSlot.values[si]] = v;
        }
      });
    } catch (_) {}
  }

  void _saveMeta() {
    try {
      final eq = <String, String>{};
      equipped.forEach((k, v) => eq[k.index.toString()] = v);
      html.window.localStorage[_metaKey] = jsonEncode({
        'fangs': fangs,
        'up': meta,
        'ach': achieved.toList(),
        'skins': ownedSkins.toList(),
        'skin': skin,
        'daily': lastDaily,
        'maxst': maxStage,
        'gear': ownedGear.toList(),
        'equip': eq,
      });
    } catch (_) {}
  }

  // ── 햅틱 큐 소비 ──
  void consumeHaptics() {
    try {
      if (optHaptic && _hapticBig) {
        HapticFeedback.heavyImpact();
      } else if (optHaptic && _hapticHit) {
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

  GPhase _lastPhase = GPhase.title;
  double _fps = 60;
  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (dt > 0.0001) _fps = _fps * 0.9 + (1.0 / dt) * 0.1; // FPS 이동평균(진단)
    final wasPlaying = world.phase == GPhase.playing;
    final sw = Stopwatch()..start();
    world.update(dt);
    sw.stop();
    world.updMs = world.updMs * 0.9 + sw.elapsedMicroseconds / 1000.0 * 0.1; // update 소요(ms)
    world.consumeHaptics();
    // 성능: 플레이 중·각성 컷신 중에는 매 프레임 리페인트. 그 외 화면은 상태 변화 시에만.
    if (mounted && (wasPlaying || world.phase == GPhase.morph || world.phase != _lastPhase)) {
      setState(() {});
    }
    _lastPhase = world.phase;
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
          // 논리 아레나는 화면보다 크게(=화면/kZoom) → 페인터가 kZoom으로 축소해 그림(줌 아웃)
          world.w = cons.maxWidth / kZoom;
          world.h = cons.maxHeight / kZoom;
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
                world.phase == GPhase.menu) _hud(),
            if (world.phase == GPhase.playing) _rageButton(),
            if (world.phase == GPhase.playing) _tinyCallButton(),
            if (world.phase == GPhase.playing && world.combo >= 5) _comboDisplay(),
            if (world.optPerf) _perfHud(),
            if (world.phase == GPhase.title) _title(),
            if (world.phase == GPhase.shop) _shopOverlay(),
            if (world.phase == GPhase.achieve) _achieveOverlay(),
            if (world.phase == GPhase.skins) _skinsOverlay(),
            if (world.phase == GPhase.status) _statusOverlay(),
            if (world.phase == GPhase.inventory) _inventoryOverlay(),
            if (world.phase == GPhase.travel) _travelOverlay(),
            if (world.phase == GPhase.options) _optionsOverlay(),
            if (world.phase == GPhase.diag) _diagOverlay(),
            if (world.phase == GPhase.morph) _morphOverlay(),
            if (world.phase == GPhase.menu) _menuOverlay(),
            if (world.phase == GPhase.levelup) _levelUp(),
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

  // ── 성능 진단 HUD (옵션) — FPS + 엔티티 수. 렉 원인 파악용 ──
  Widget _perfHud() {
    final w = world;
    final fps = _fps.round();
    final col = fps >= 50 ? P.green : (fps >= 30 ? P.gold : P.red);
    return Positioned(
      top: 2,
      left: 6,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$fps fps  up${w.updMs.toStringAsFixed(1)} pt${w.paintMs.toStringAsFixed(1)}ms\n'
            '적${w.enemies.length} 탄${w.bullets.length} 구${w.orbs.length} 픽${w.pickups.length} '
            '입${w.parts.length} 펄${w.pulses.length} 적탄${w.eBullets.length}',
            style: TextStyle(
                color: col, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }

  // ── 콤보 카운터 — 연속 처치 고조(검증된 도파민). 콤보 높을수록 색·크기↑ ──
  Widget _comboDisplay() {
    final c = world.combo;
    final col = c >= 40 ? P.red : (c >= 20 ? const Color(0xFFE8702E) : P.gold);
    // 막 갱신됐을 때 살짝 팝(comboT가 2.4에서 시작해 줄어듦)
    final fresh = (world.comboT / 2.4).clamp(0.0, 1.0);
    final pop = 1.0 + (fresh > 0.85 ? (fresh - 0.85) * 1.6 : 0.0);
    return Positioned(
      top: 64,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Transform.scale(
            scale: pop,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('🔥 $c 연속',
                  style: TextStyle(
                      color: col,
                      fontSize: 22 + (c >= 20 ? 6.0 : 0.0),
                      fontWeight: FontWeight.bold,
                      shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
              Text('공격 +${((world.comboDmg - 1) * 100).round()}%',
                  style: TextStyle(
                      color: col.withOpacity(0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
            ]),
          ),
        ),
      ),
    );
  }

  // ── 타이니 호출 버튼 (시리/빅스비식) — 어흥 버튼 위(좌하단). 불투명 ──
  Widget _tinyCallButton() {
    return Positioned(
      left: 34,
      bottom: 110,
      child: GestureDetector(
        onTap: () => setState(() => world.openMenu()),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: P.panel,
            border: Border.all(color: P.gold, width: 1.8),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 6)],
          ),
          child: const Text('🐯', style: TextStyle(fontSize: 22)),
        ),
      ),
    );
  }

  // ── 일시정지 허브 (타이니 호출) — 현황 + 이어하기 + 타일 그리드. 통일된 레이아웃 ──
  Widget _menuOverlay() {
    return Container(
      color: const Color(0xF20A0806),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🐯  잠시 숨 고르기',
              style: TextStyle(color: P.gold, fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          // 현황 카드
          Container(
            width: 320,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: P.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: world.threatColor.withOpacity(0.7)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _miniStat('사냥터', 'STAGE ${world.stage}', world.threatColor),
              _miniStat('생존', World.mmss(world.time), P.parch),
              _miniStat('처치', '${world.kills}', P.red),
              _miniStat('🦷', '${world.fangs}', P.goldSoft),
            ]),
          ),
          const SizedBox(height: 14),
          // 주 동작: 이어하기 / 사냥터 이동
          SizedBox(
            width: 320,
            child: Row(children: [
              Expanded(
                  child: _actBtn('▶  이어하기', P.gold, true,
                      () => setState(() => world.resume()))),
              const SizedBox(width: 10),
              Expanded(
                  child: _actBtn('🗺  사냥터', P.cyan, true,
                      () => setState(() => world.phase = GPhase.travel))),
            ]),
          ),
          const SizedBox(height: 14),
          // 허브 타일 그리드 (단련/장비/창고/업적/무늬/설정)
          SizedBox(width: 320, child: _hubGrid(from: GPhase.menu)),
          const SizedBox(height: 14),
          SizedBox(
            width: 320,
            child: _actBtn('🏠  소굴로 (세이브 선택)', P.panel, false,
                () => setState(() => world.phase = GPhase.title)),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: 320,
            child: _actBtn('🐞  치트: +10 레벨', const Color(0xFF24301F), false,
                () => setState(() => world.cheatLevel10())),
          ),
        ]),
      ),
    );
  }

  // 통일 액션 버튼 (full/expanded용). primary=강조(밝은색), 아니면 패널 테두리.
  Widget _actBtn(String t, Color c, bool primary, VoidCallback onTap) => Material(
        color: primary ? c : P.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: primary
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(14), border: Border.all(color: P.line)),
            child: Text(t,
                style: TextStyle(
                    color: primary ? Colors.black : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      );

  Widget _miniStat(String label, String val, Color c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: P.muted, fontSize: 10)),
          const SizedBox(height: 2),
          Text(val, style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      );

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

  // 세이브 삭제 확인 — 실수 방지(되돌릴 수 없음)
  void _confirmDeleteSlot(int n) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: P.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('세이브 삭제', style: TextStyle(color: P.parch, fontWeight: FontWeight.bold)),
        content: Text('슬롯 $n의 송곳니·강화·업적·기록이 모두 사라집니다.\n되돌릴 수 없습니다. 삭제할까요?',
            style: const TextStyle(color: P.muted, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소', style: TextStyle(color: P.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => world.deleteSlot(n));
            },
            child: const Text('삭제', style: TextStyle(color: P.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
              return Stack(children: [
                GestureDetector(
                  onTap: () => setState(() => world.selectSlot(n)),
                  child: Container(
                    width: 98,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.fromLTRB(5, 9, 5, 9),
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
                ),
                // 세이브 삭제 (데이터 있는 슬롯만) — 두 번 눌러 확인
                if (info != null)
                  Positioned(
                    top: 2,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => _confirmDeleteSlot(n),
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: P.blood.withOpacity(0.9),
                          border: Border.all(color: Colors.white.withOpacity(0.6)),
                        ),
                        child: const Text('✕',
                            style: TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ]);
            }),
          ),
          const SizedBox(height: 18),
          // 단일 주인공 — 호랑이가 되고 싶은 양 (사냥할수록 호랑이로 변신)
          Container(
            width: 230,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: sel.color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel.color, width: 2),
            ),
            child: Column(children: [
              const Text('🐑  →  🐯', style: TextStyle(fontSize: 26)),
              const SizedBox(height: 6),
              Text(sel.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(sel.desc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: P.parch, fontSize: 12, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 10),
          if (world.bestTime > 0)
            Text('최고 기록 ${World.mmss(world.bestTime)} · ${world.bestKills}킬',
                style: const TextStyle(color: P.muted, fontSize: 12)),
          const SizedBox(height: 14),
          _startStagePicker(),
          const SizedBox(height: 12),
          _bigBtn(world.maxStage > 1 ? '⚔  STAGE ${world.startStage} 생존 시작' : '⚔  생존 시작',
              sel.color, () => setState(() => world.startGame(atStage: world.startStage))),
          const SizedBox(height: 16),
          // 통일 허브 그리드 (단련/장비/창고/업적/무늬/설정)
          SizedBox(width: 320, child: _hubGrid(from: GPhase.title)),
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
      color: const Color(0xF20A0806),
      child: SafeArea(
        child: Column(children: [
          _ohead('💪', '단련'),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 4),
            child: Text('송곳니로 영구히 강해진다 — 죽음은 헛되지 않는다',
                style: TextStyle(color: P.muted, fontSize: 11.5)),
          ),
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
          _backBar(world.shopReturn),
        ]),
      ),
    );
  }

  // ── 무늬(스킨) ──
  Widget _skinsOverlay() {
    return Container(
      color: const Color(0xF20A0806),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(children: [
              const Text('🎨 무늬',
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
          _backBar(world.statusReturn),
        ]),
      ),
    );
  }

  // ── 장비 · 능력치 — 시작 스탯 + 장착 슬롯 ──
  Widget _statusOverlay() {
    final dmgP = (5 * world.metaLv('atk') + world.gearStat('dmg')).round();
    final asP = world.gearStat('as').round();
    final hpV = (world.baseMaxHp + 15 * world.metaLv('hp') + world.gearStat('hp')).round();
    final spdP = (4 * world.metaLv('spd') + world.gearStat('spd')).round();
    final pickV = (58 + 8 * world.metaLv('pick') + world.gearStat('pick')).round();
    final regenV = world.gearStat('regen');
    final inRun = world.statusReturn == GPhase.menu;
    return Container(
      color: const Color(0xF20A0806),
      child: SafeArea(
        child: Column(children: [
          _ohead('🛡', '장비 · 능력치'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              children: [
                _portraitCard(),
                const SizedBox(height: 14),
                const Text('능력치 (영구: 강화 + 장비)',
                    style: TextStyle(color: P.goldSoft, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _statBox('💪 공격력', '+$dmgP%'),
                  _statBox('⚡ 공격속도', '+$asP%'),
                  _statBox('❤ 최대체력', '$hpV'),
                  _statBox('🌬 이동속도', '+$spdP%'),
                  _statBox('🧲 수집범위', '$pickV'),
                  _statBox('💗 재생', regenV > 0 ? '${regenV.toStringAsFixed(1)}/s' : '–'),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: P.blood.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: P.blood.withOpacity(0.5)),
                  ),
                  child: Row(children: [
                    const Text('🍖', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('포식 성장 (먹을수록 누적·연속)',
                            style: TextStyle(color: P.goldSoft, fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(
                            '처치 ${world.devour} · 공격 +${(world.devourAtk * 100).round()}% · 공속 +${(world.devourAs * 100).round()}%',
                            style: const TextStyle(color: P.parch, fontSize: 11)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text('장착 중인 장비',
                    style: TextStyle(color: P.goldSoft, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _equipSlotRow(GearSlot.weapon, '무기'),
                _equipSlotRow(GearSlot.armor, '방어구'),
                _equipSlotRow(GearSlot.trinket, '장신구'),
                const SizedBox(height: 10),
                _bigBtn('🎒  인벤토리에서 장착 · 구매', P.cyan,
                    () => setState(() => world.phase = GPhase.inventory)),
                if (inRun) ...[
                  const SizedBox(height: 16),
                  const Text('이번 런 빌드',
                      style: TextStyle(color: P.goldSoft, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Center(child: _statusPanel()),
                ],
              ],
            ),
          ),
          _backBar(world.statusReturn),
        ]),
      ),
    );
  }

  // 장착 슬롯 한 줄 (비어있으면 안내) — 탭하면 인벤토리로
  Widget _equipSlotRow(GearSlot s, String label) {
    final id = world.equipped[s];
    final g = id == null ? null : world.gearById(id);
    final rc = g == null ? P.muted : kRarityCol[g.rarity];
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: GestureDetector(
        onTap: () => setState(() => world.phase = GPhase.inventory),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: P.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: g == null ? P.line : rc.withOpacity(0.7)),
          ),
          child: Row(children: [
            SizedBox(
                width: 46,
                child: Text(label, style: const TextStyle(color: P.muted, fontSize: 11))),
            Text(g == null ? '· ' : '${g.icon} ', style: const TextStyle(fontSize: 18)),
            Expanded(
              child: Text(g == null ? '비어 있음' : g.name,
                  style: TextStyle(
                      color: g == null ? P.muted : rc,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold)),
            ),
            Text(g == null ? '' : g.desc,
                style: const TextStyle(color: P.muted, fontSize: 9.5)),
          ]),
        ),
      ),
    );
  }

  // ── 창고 / 대장간 — 보유·구매 장비 목록(장착/구매) ──
  Widget _inventoryOverlay() {
    return Container(
      color: const Color(0xF20A0806),
      child: SafeArea(
        child: Column(children: [
          _ohead('🎒', '창고 · 대장간'),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 4),
            child: Text('보유 장비는 [장착], 미보유는 🦷로 대장간 구매. 슬롯당 1개.',
                style: TextStyle(color: P.muted, fontSize: 11)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              children: kGear.map((g) => _gearRow(g)).toList(),
            ),
          ),
          _backBar(GPhase.status, label: '장비로'),
        ]),
      ),
    );
  }

  // ── 사냥터 이동 (전용 화면) — STAGE 버튼으로 선택·이동 ──
  Widget _travelOverlay() {
    return Container(
      color: const Color(0xF20A0806),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🗺 사냥터 이동',
              style: TextStyle(color: P.gold, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('현재 STAGE ${world.stage} · 최고 ${world.maxStage}',
              style: const TextStyle(color: P.muted, fontSize: 12)),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: List.generate(world.maxStage, (i) {
                final n = i + 1;
                final cur = n == world.stage;
                final dc = world.diffForStage(n);
                final col = dc < 1.0 ? P.green : (dc < 1.6 ? P.gold : P.red);
                return GestureDetector(
                  onTap: () => setState(() => world.travelToStage(n)),
                  child: Container(
                    width: 54,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cur ? P.gold : Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cur ? P.gold : col.withOpacity(0.7), width: cur ? 2 : 1),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$n',
                          style: TextStyle(
                              color: cur ? Colors.black : P.parch,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text('×${dc.toStringAsFixed(1)}',
                          style: TextStyle(
                              color: cur ? Colors.black : col, fontSize: 9, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          const Text('낮추면 수월 · 올리면 적 강함 + XP·전리품↑ (탭하면 즉시 이동)',
              textAlign: TextAlign.center, style: TextStyle(color: P.muted, fontSize: 10.5)),
          const SizedBox(height: 18),
          SizedBox(
              width: 320,
              child: _actBtn('✕  닫기', P.panel, false,
                  () => setState(() => world.phase = GPhase.menu))),
        ]),
      ),
    );
  }

  // ── 옵션 (설정) — 검증된 핵심 옵션. 전역 저장 ──
  Widget _optionsOverlay() {
    return Container(
      color: const Color(0xF20A0806),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⚙ 옵션',
              style: TextStyle(color: P.gold, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _toggleRow('🔊 소리', !world.sfx.muted, () => setState(() {
                world.toggleMute();
                world.saveOpts();
              })),
          _toggleRow('📳 진동(햅틱)', world.optHaptic, () => setState(() {
                world.optHaptic = !world.optHaptic;
                world.saveOpts();
              })),
          _toggleRow('🫨 화면 흔들림', world.optShake, () => setState(() {
                world.optShake = !world.optShake;
                world.saveOpts();
              })),
          _toggleRow('⚡ 화면 번쩍임 (광과민 주의)', world.optFlash, () => setState(() {
                world.optFlash = !world.optFlash;
                world.saveOpts();
              })),
          _toggleRow('🔢 데미지 숫자', world.optDmgNum, () => setState(() {
                world.optDmgNum = !world.optDmgNum;
                world.saveOpts();
              })),
          _toggleRow('📊 성능 정보 (FPS·수)', world.optPerf, () => setState(() {
                world.optPerf = !world.optPerf;
                world.saveOpts();
              })),
          const SizedBox(height: 6),
          SizedBox(
              width: 300,
              child: _actBtn('🔬  진단 로그 (복사)', P.cyan, false,
                  () => setState(() => world.phase = GPhase.diag))),
          const SizedBox(height: 8),
          // 조이스틱 위치
          Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: P.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: P.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🕹 조이스틱 위치',
                  style: TextStyle(color: P.parch, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                _joyPosBtn('왼쪽', 0),
                const SizedBox(width: 8),
                _joyPosBtn('엄지존(권장)', 1),
                const SizedBox(width: 8),
                _joyPosBtn('오른쪽', 2),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
          SizedBox(
              width: 320,
              child: _actBtn('✕  닫기', P.panel, false,
                  () => setState(() => world.phase = world.statusReturn))),
        ]),
      ),
    );
  }

  Widget _toggleRow(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: P.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: P.line),
            ),
            child: Row(children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          color: P.parch, fontSize: 14, fontWeight: FontWeight.bold))),
              Container(
                width: 50,
                height: 26,
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: on ? P.gold.withOpacity(0.85) : Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: on ? P.gold : P.line),
                ),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _joyPosBtn(String label, int v) {
    final on = world.joyPos == v;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          world.joyPos = v;
          world.saveOpts();
        }),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? P.gold : Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: on ? P.gold : P.line),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Colors.black : P.parch, fontSize: 12.5, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // ── 진단 로그 — 상세 성능/기기 정보 + 텍스트 복사 ──
  String _diagText() {
    final w = world;
    String ua = '';
    double dpr = 1;
    int iw = 0, ih = 0;
    try {
      ua = html.window.navigator.userAgent;
      dpr = html.window.devicePixelRatio.toDouble();
      iw = html.window.innerWidth ?? 0;
      ih = html.window.innerHeight ?? 0;
    } catch (_) {}
    final pw = (iw * dpr).round(), ph = (ih * dpr).round();
    return '[어흥 진단]\n'
        'fps ${_fps.toStringAsFixed(1)} | update ${w.updMs.toStringAsFixed(2)}ms | paint ${w.paintMs.toStringAsFixed(2)}ms\n'
        'phase ${w.phase.name} stage ${w.stage} t ${w.time.toStringAsFixed(0)}s lv ${w.level} combo ${w.combo}\n'
        '엔티티: 적 ${w.enemies.length} / 탄 ${w.bullets.length} / 적탄 ${w.eBullets.length} / 구슬 ${w.orbs.length} / 픽업 ${w.pickups.length} / 입자 ${w.parts.length} / 펄스 ${w.pulses.length} / 플로트 ${w.floats.length}\n'
        '화면 ${iw}x$ih DPR ${dpr.toStringAsFixed(2)} 물리 ${pw}x$ph | zoom $kZoom | renderer html\n'
        'UA $ua';
  }

  void _copyDiag() {
    try {
      Clipboard.setData(ClipboardData(text: _diagText())); // flutter/services — 웹 호환
    } catch (_) {}
  }

  Widget _diagOverlay() {
    return Container(
      color: const Color(0xF20A0806),
      child: SafeArea(
        child: Column(children: [
          _ohead('🔬', '진단 로그', fangs: false),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: P.line),
                ),
                child: SelectableText(
                  _diagText(),
                  style: const TextStyle(
                      color: P.parch, fontSize: 11.5, height: 1.5, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: _actBtn('📋  텍스트 복사', P.gold, true, () {
              _copyDiag();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('진단 로그를 복사했습니다'), duration: Duration(seconds: 1)));
            }),
          ),
          _backBar(GPhase.options),
        ]),
      ),
    );
  }

  // ── 초상화 진급 '짜잔' 컷신 — 새 초상화 공개 + 능력치 상승 + 탭하여 계속 ──
  Widget _morphOverlay() {
    final c = world.morphClock;
    final pt = kPortraits[world.portraitTier.clamp(0, kPortraits.length - 1)];
    final prev = kPortraits[world.morphFromTier.clamp(0, kPortraits.length - 1)];
    final titleA = ((c - 0.35) / 0.35).clamp(0.0, 1.0);
    final titlePop = 0.6 + 0.4 * titleA + (c < 0.9 ? sin(titleA * 3.14) * 0.15 : 0.0);
    // 능력치 상승분(이전 단계 대비)
    final gains = <String>[];
    void g(String k, String label, String unit) {
      final d = (pt.bonus[k] ?? 0) - (prev.bonus[k] ?? 0);
      if (d > 0) gains.add('$label +${d.round()}$unit');
    }

    g('dmg', '공격', '%');
    g('as', '공속', '%');
    g('hp', '체력', '');
    g('spd', '이동', '%');
    final blink = (c % 1.0) < 0.5;
    return GestureDetector(
      onTap: () => setState(() => world.dismissMorph()),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: MorphPainter(world))),
        // 이전 / 지금 라벨 (아바타 아래)
        Align(
          alignment: const Alignment(-0.46, 0.06),
          child: Opacity(
            opacity: titleA * 0.8,
            child: Text(prev.name,
                style: const TextStyle(color: P.muted, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
        Align(
          alignment: const Alignment(0.46, 0.06),
          child: Opacity(
            opacity: titleA,
            child: const Text('NEW!',
                style: TextStyle(color: P.gold, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ),
        // 새 초상화 이름 (위)
        Align(
          alignment: const Alignment(0, -0.62),
          child: Transform.scale(
            scale: titlePop,
            child: Opacity(
              opacity: titleA,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('— 진 급 —',
                    style: TextStyle(color: P.goldSoft, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 3)),
                const SizedBox(height: 4),
                Text(pt.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: P.gold,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(color: P.blood.withOpacity(0.9), blurRadius: 16),
                          const Shadow(color: Colors.black, blurRadius: 6),
                        ])),
              ]),
            ),
          ),
        ),
        // 설명 + 능력치 상승 (아래)
        Align(
          alignment: const Alignment(0, 0.45),
          child: Opacity(
            opacity: titleA,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(pt.desc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: P.parch, fontSize: 13.5, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
              if (gains.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: P.gold.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: P.gold.withOpacity(0.6)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('능력치 상승!',
                        style: TextStyle(color: P.goldSoft, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('▲  ${gains.join("   ")}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: P.green, fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ],
              const SizedBox(height: 22),
              Opacity(
                opacity: c > 0.4 ? (blink ? 1.0 : 0.35) : 0.0,
                child: const Text('👆 탭하여 계속',
                    style: TextStyle(color: P.muted, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // 초상화 시스템 카드 — 현재 단계 + 진급 경로(레벨별). 진급마다 능력치 상승.
  Widget _portraitCard() {
    final cur = world.portraitTier.clamp(0, kPortraits.length - 1);
    final p = kPortraits[cur];
    final next = cur + 1 < kPortraits.length ? kPortraits[cur + 1] : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: P.gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.gold.withOpacity(0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🖼 초상화', style: TextStyle(color: P.goldSoft, fontSize: 13, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(p.name, style: const TextStyle(color: P.gold, fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Row(
          children: List.generate(kPortraits.length, (i) {
            final reached = i <= cur;
            final on = i == cur;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < kPortraits.length - 1 ? 5 : 0),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on
                      ? P.gold
                      : (reached ? P.gold.withOpacity(0.3) : Colors.black.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: reached ? P.gold.withOpacity(0.7) : P.line),
                ),
                child: Text('Lv${kPortraits[i].reqLevel}',
                    style: TextStyle(
                        color: on ? Colors.black : (reached ? P.goldSoft : P.muted),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(p.desc, style: const TextStyle(color: P.parch, fontSize: 11.5)),
        if (next != null) ...[
          const SizedBox(height: 3),
          Text('다음 진급: Lv ${next.reqLevel} → ${next.name} (능력치↑)',
              style: const TextStyle(color: P.muted, fontSize: 10.5)),
        ],
      ]),
    );
  }

  Widget _statBox(String label, String val) => Container(
        width: 102,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: P.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: P.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: P.muted, fontSize: 11)),
          const SizedBox(height: 3),
          Text(val, style: const TextStyle(color: P.goldSoft, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _gearRow(Gear g) {
    final owned = world.ownedGear.contains(g.id);
    final equippedHere = world.equipped[g.slot] == g.id;
    final rc = kRarityCol[g.rarity];
    final canBuy = !owned && world.fangs >= g.cost;
    final btnColor = equippedHere
        ? const Color(0xFF2A2018)
        : (owned ? P.green.withOpacity(0.85) : (canBuy ? P.gold : const Color(0xFF2A2018)));
    final btnText = equippedHere ? '장착중' : (owned ? '장착' : '🦷${g.cost}');
    final slotName = g.slot == GearSlot.weapon ? '무기' : (g.slot == GearSlot.armor ? '방어구' : '장신구');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: equippedHere ? rc.withOpacity(0.14) : P.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: equippedHere ? rc : P.line, width: equippedHere ? 2 : 1),
        ),
        child: Row(children: [
          Text(g.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: rc.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
                  child: Text('${kRarityName[g.rarity]}·$slotName',
                      style: TextStyle(color: rc, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Text(g.name,
                    style: TextStyle(color: rc, fontSize: 13.5, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 2),
              Text(g.desc, style: const TextStyle(color: P.muted, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Material(
              color: btnColor,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: equippedHere
                    ? null
                    : () => setState(() => owned ? world.equipGear(g.id) : world.buyGear(g.id)),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(btnText,
                      style: TextStyle(
                          color: equippedHere
                              ? P.muted
                              : (owned ? Colors.black : (canBuy ? Colors.black : P.muted)),
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 업적 ──
  Widget _achieveOverlay() {
    return Container(
      color: const Color(0xF20A0806),
      child: SafeArea(
        child: Column(children: [
          _ohead('🏆', '업적', fangs: false, trailing: '${world.achieved.length} / ${kAch.length}'),
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
          _backBar(world.statusReturn),
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
        Text(world.specialChoice ? '✨ 특별 스킬' : '⚡ LEVEL UP',
            style: TextStyle(
                color: world.specialChoice ? P.purple : P.gold,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 3)),
        const SizedBox(height: 4),
        Text(world.specialChoice ? 'Lv ${world.level} · 판을 뒤집을 한 방을 고르십시오' : 'Lv ${world.level}',
            style: const TextStyle(color: P.muted, fontSize: 13)),
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
      child: SingleChildScrollView(
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
        const SizedBox(height: 16),
        _startStagePicker(),
        const SizedBox(height: 16),
        _bigBtn('🔥  STAGE ${world.startStage} 에서 다시 일어선다', P.blood,
            () => setState(() => world.startGame(atStage: world.startStage)), dark: false),
        const SizedBox(height: 10),
        _bigBtn('🦷  전리품 상점', P.panel, () => setState(() {
              world.shopReturn = GPhase.dead;
              world.phase = GPhase.shop;
            }), dark: false),
        const SizedBox(height: 10),
        _bigBtn('📊  상태 · 장비', P.panel, () => setState(() {
              world.statusReturn = GPhase.dead;
              world.phase = GPhase.status;
            }), dark: false),
        const SizedBox(height: 10),
        _bigBtn('🏠  타이틀로', P.panel, () => setState(() => world.phase = GPhase.title),
            dark: false),
      ]),
      ),
    );
  }

  // 시작 스테이지 선택기 — 사망/타이틀에서 버튼으로 시작 사냥터 고르기(도달한 최고까지)
  Widget _startStagePicker() {
    if (world.maxStage <= 1) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: P.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: P.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🗺  시작 사냥터 (탭하여 선택)',
            style: TextStyle(color: P.goldSoft, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(world.maxStage, (i) {
            final n = i + 1;
            final on = n == world.startStage;
            return GestureDetector(
              onTap: () => setState(() => world.startStage = n),
              child: Container(
                width: 38,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? P.gold : Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: on ? P.gold : P.line),
                ),
                child: Text('$n',
                    style: TextStyle(
                        color: on ? Colors.black : P.parch,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text('STAGE↑ = 적 강함 · XP·전리품 ↑ · 그만큼 강한 시작 빌드(무기·레벨)로 출발',
            style: const TextStyle(color: P.muted, fontSize: 10)),
      ]),
    );
  }

  // 내 빌드(스킬·패시브·레벨) 상태 — 타이니 메뉴에서 확인
  Widget _statusPanel() {
    final chips = <Widget>[];
    void add(String ic, String nm, int lv, [bool evo = false]) {
      if (lv <= 0) return;
      chips.add(_statChip('$ic $nm ${evo ? "★진화" : "Lv$lv"}'));
    }

    add('🪝', '발톱', world.clawLv, world.clawEvo);
    add('🦷', '송곳니', world.fangLv, world.fangEvo);
    add('💢', '포효', world.roarLv, world.roarEvo);
    add('⚡', '벼락', world.boltLv);
    add('🌵', '가시밭', world.spikeLv);
    add('🐅', '야성', world.wildLv);
    add('🛡', '가죽', world.hideLv);
    add('🌬', '바람', world.windLv);
    add('🧲', '굶주림', world.hungerLv);
    add('🔥', '분노', world.rageLv);
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: P.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('내 빌드  ·  Lv ${world.level}  ·  ❤ ${world.hp.ceil()}/${world.maxHp.round()}',
            style: const TextStyle(color: P.goldSoft, fontSize: 12.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: chips.isEmpty ? [_statChip('아직 강화 없음')] : chips,
        ),
      ]),
    );
  }

  Widget _statChip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: P.line),
        ),
        child: Text(t, style: const TextStyle(color: P.parch, fontSize: 10.5)),
      );

  Widget _stageBtn(String label, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? P.gold.withOpacity(0.85) : const Color(0xFF2A2018),
          border: Border.all(color: enabled ? P.gold : P.line),
        ),
        child: Text(label,
            style: TextStyle(
                color: enabled ? Colors.black : P.muted, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
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

  // ── 통일 컴포넌트 (전면 개편) ──
  // 모든 오버레이 공용 헤더: 아이콘 + 제목 + (선택)송곳니
  Widget _ohead(String icon, String title, {bool fangs = true, String? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 9),
          Text(title, style: const TextStyle(color: P.gold, fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (trailing != null)
            Text(trailing,
                style: const TextStyle(color: P.goldSoft, fontSize: 14, fontWeight: FontWeight.bold))
          else if (fangs)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: P.gold.withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: P.gold.withOpacity(0.5)),
              ),
              child: Text('🦷 ${world.fangs}',
                  style: const TextStyle(color: P.goldSoft, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
        ]),
      );

  // 공용 하단 닫기 바
  Widget _backBar(GPhase to, {String label = '닫기'}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: _bigBtn('✕  $label', P.panel, () => setState(() => world.phase = to), dark: false),
      );

  // 리스트형 오버레이 공용 골격 (스크림+헤더+본문+닫기) — 통일성
  Widget _ovl(String icon, String title, List<Widget> body, GPhase backTo,
          {bool fangs = true, String backLabel = '닫기'}) =>
      Container(
        color: const Color(0xF20A0806),
        child: SafeArea(
          child: Column(children: [
            _ohead(icon, title, fangs: fangs),
            Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), children: body)),
            _backBar(backTo, label: backLabel),
          ]),
        ),
      );

  // 네비 타일 (허브 그리드) — 직관적 아이콘 타일
  Widget _navTile(String icon, String title, Color accent, VoidCallback onTap, {String sub = ''}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 98,
          height: 92,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: P.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.55), width: 1.4),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(icon, style: const TextStyle(fontSize: 27)),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
            if (sub.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(sub, style: const TextStyle(color: P.muted, fontSize: 9)),
              ),
          ]),
        ),
      );

  // 허브 타일 그리드 (타이틀·일시정지 공용) — 일관된 메뉴 진입
  Widget _hubGrid({required GPhase from}) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        _navTile('💪', '단련', P.gold, () => setState(() {
              world.shopReturn = from;
              world.phase = GPhase.shop;
            }), sub: '영구 강화'),
        _navTile('🛡', '장비', P.cyan, () => setState(() {
              world.statusReturn = from;
              world.phase = GPhase.status;
            }), sub: '능력치'),
        _navTile('🎒', '창고', P.green, () => setState(() {
              world.statusReturn = from;
              world.phase = GPhase.inventory;
            }), sub: '장비 획득'),
        _navTile('🏆', '업적', P.goldSoft, () => setState(() {
              world.statusReturn = from;
              world.phase = GPhase.achieve;
            }), sub: '${world.achieved.length}/${kAch.length}'),
        _navTile('🎨', '무늬', P.purple, () => setState(() {
              world.statusReturn = from;
              world.phase = GPhase.skins;
            }), sub: '${world.ownedSkins.length}/${kSkins.length}'),
        _navTile('⚙', '설정', P.muted, () => setState(() {
              world.statusReturn = from;
              world.phase = GPhase.options;
            })),
      ],
    );
  }
}

// =============================================================================
//  월드 페인터 — 네온 벡터 (어두운 배경 + 발광 레이어). 전부 코드 생성.
// =============================================================================
class WorldPainter extends CustomPainter {
  final World w;
  WorldPainter(this.w);

  // 스테이지 배경 테마 — 3스테이지마다 분위기 전환(반복 맵의 단조로움 해소, 근거: 장르 지루함 1순위).
  //  [내부색, 외곽색, 그리드색, 부유 모트색] · 코드 전용.
  static const List<List<Color>> _themes = [
    [Color(0xFF15110C), Color(0xFF070605), Color(0x12E8A33D), Color(0x1FE8A33D)], // 둥지(황혼 황금)
    [Color(0xFF1A0D0B), Color(0xFF0A0504), Color(0x12E5604E), Color(0x1FE5604E)], // 핏빛 전장
    [Color(0xFF0D1018), Color(0xFF05070A), Color(0x125FD0E0), Color(0x1F5FD0E0)], // 시린 한밤
    [Color(0xFF120A1A), Color(0xFF070409), Color(0x12B07CE0), Color(0x1FB07CE0)], // 보라 의회
    [Color(0xFF0A1410), Color(0xFF050806), Color(0x127FD08A), Color(0x1F7FD08A)], // 비취 심림
  ];

  int get _ti => (((w.stage - 1) ~/ 3) % _themes.length).clamp(0, _themes.length - 1);

  // 발광 점: 큰 후광 → 작은 후광 → 밝은 코어 (HTML 렌더러 호환, maskFilter 미사용)
  void _glow(Canvas c, double x, double y, double r, Color col, {double core = 1.0}) {
    c.drawCircle(Offset(x, y), r * 2.6, Paint()..color = col.withOpacity(0.09));
    c.drawCircle(Offset(x, y), r * 1.6, Paint()..color = col.withOpacity(0.18));
    c.drawCircle(Offset(x, y), r, Paint()..color = col.withOpacity(core));
  }

  // 이모지 TextPainter 캐시 — 매 프레임 layout() 비용 제거(웹에서 매우 비쌈). 고정 크기로 1회 레이아웃 후 재사용.
  static final Map<String, TextPainter> _emojiCache = {};
  TextPainter _emoji(String s, double size) {
    final key = '$s|${size.round()}';
    var tp = _emojiCache[key];
    if (tp == null) {
      tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size)),
        textDirection: TextDirection.ltr,
      )..layout();
      _emojiCache[key] = tp;
    }
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final _sw = Stopwatch()..start();
    final th = _themes[_ti];
    // 배경 — 화면 전체. 셰이더 캐시(크기·테마 동일하면 재사용 → 매 프레임 생성 비용 제거)
    final key = '${size.width.round()}x${size.height.round()}_$_ti';
    if (w.bgShader == null || w.bgKey != key) {
      w.bgShader = RadialGradient(colors: [th[0], th[1]], radius: 1.0)
          .createShader(Offset.zero & size);
      w.bgKey = key;
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = w.bgShader);

    // 줌 아웃 — 논리 아레나(=화면/kZoom)를 축소해 더 넓어 보이게. UI(플래시·조이스틱)는 줌 밖.
    canvas.save();
    canvas.scale(kZoom, kZoom);
    if (w.optShake && w.shake > 0.2) {
      canvas.translate(sin(w.time * 91.0) * w.shake, cos(w.time * 73.0) * w.shake);
    }
    final lsize = Size(w.w, w.h); // 논리 크기
    _grid(canvas, lsize, th[2]);
    _motes(canvas, lsize, th[3]);

    if (w.phase == GPhase.title) {
      canvas.restore();
      return;
    }

    // 마나 구슬 — 단일 원(성능)
    final orbCore = Paint()..color = P.cyan;
    for (final o in w.orbs) {
      canvas.drawCircle(Offset(o.x, o.y), 3.2, orbCore);
    }

    // 바닥 파워업 픽업 — 발광 + 아이콘(이모지 캐시 사용, 매 프레임 layout 제거)
    for (final pk in w.pickups) {
      final col = pk.type == PickType.magnet
          ? P.cyan
          : (pk.type == PickType.bomb ? const Color(0xFFE8702E) : P.green);
      final ic = pk.type == PickType.magnet ? '🧲' : (pk.type == PickType.bomb ? '💣' : '❤');
      final blink = pk.life < 3 ? (sin(w.time * 14) * 0.4 + 0.6) : 1.0;
      _glow(canvas, pk.x, pk.y, 11.0, col, core: 0.5 * blink);
      final tp = _emoji(ic, 18);
      tp.paint(canvas, Offset(pk.x - tp.width / 2, pk.y - tp.height / 2));
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

    // 투사체 (발톱) — 잔상 + 코어 (성능: Paint 재사용, 글로우 2겹)
    final bTrail = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = P.gold.withOpacity(0.4);
    final bHalo = Paint()..color = P.goldSoft.withOpacity(0.3);
    final bCore = Paint()..color = P.goldSoft;
    for (final b in w.bullets) {
      canvas.drawLine(Offset(b.x - b.vx * 0.028, b.y - b.vy * 0.028), Offset(b.x, b.y), bTrail);
      canvas.drawCircle(Offset(b.x, b.y), b.radius * 1.4, bHalo);
      canvas.drawCircle(Offset(b.x, b.y), b.radius * 0.7, bCore);
    }

    // 원거리 적 투사체 (붉은 — 위협)
    final eTrail = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = P.red.withOpacity(0.4);
    final eHalo = Paint()..color = P.red.withOpacity(0.25);
    final eCore = Paint()..color = P.red;
    for (final b in w.eBullets) {
      canvas.drawLine(Offset(b.x - b.vx * 0.03, b.y - b.vy * 0.03), Offset(b.x, b.y), eTrail);
      canvas.drawCircle(Offset(b.x, b.y), 7.0, eHalo);
      canvas.drawCircle(Offset(b.x, b.y), 3.5, eCore);
    }

    // 회전 송곳니 (진화 시 더 많고 크게)
    if (w.fangLv > 0) {
      final cnt = w.fangLv + (w.fangEvo ? 3 : 0);
      final orad = (60 + w.fangLv * 4.0) * (w.fangEvo ? 1.4 : 1.0);
      final fHalo = Paint()..color = P.cyan.withOpacity(0.25);
      final fCore = Paint()..color = P.cyan;
      final fr = w.fangEvo ? 8.0 : 6.0;
      for (int i = 0; i < cnt; i++) {
        final a = w.orbitAngle + i * 6.2831853 / cnt;
        final fx = w.px + cos(a) * orad, fy = w.py + sin(a) * orad;
        canvas.drawCircle(Offset(fx, fy), fr * 1.6, fHalo);
        canvas.drawCircle(Offset(fx, fy), fr, fCore);
      }
    }

    // 파티클 (발광 스파크) — 단일 원(성능)
    for (final pt in w.parts) {
      final a = (pt.life / pt.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
          Offset(pt.x, pt.y), pt.size * a + 0.6, Paint()..color = pt.color.withOpacity(a));
    }

    // 플레이어 (백호 — 네온 골드)
    _player(canvas);
    // 펫 타이니 (졸졸 따라다니며 표정 반응)
    _pet(canvas);

    // 데미지 숫자 (옵션으로 끌 수 있음)
    if (w.optDmgNum) {
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
    }

    canvas.restore();

    // 스크린 플래시 — 옵션 ON일 때만(광과민 접근성). 절제된 세기.
    if (w.optFlash && w.flashT > 0) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = w.flashCol.withOpacity((w.flashT * 0.4).clamp(0.0, 0.32)));
    }

    // 진단: 페인트 소요(ms) 기록
    _sw.stop();
    w.paintMs = w.paintMs * 0.9 + _sw.elapsedMicroseconds / 1000.0 * 0.1;

    // 방향키 — 옵션 위치. 기본=엄지존(가운데-오른쪽, 검증된 오른손 엄지 자연 위치). 노브는 진행 방향.
    if (w.phase != GPhase.playing) return;
    final jcx =
        w.joyPos == 0 ? size.width * 0.32 : (w.joyPos == 2 ? size.width - 70.0 : size.width * 0.66);
    final jx = jcx, jy = size.height - 78.0, baseR = 46.0;
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

  void _grid(Canvas canvas, Size size, Color col) {
    final g = Paint()
      ..color = col
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), g);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
  }

  // 부유 모트 — 테마색의 입자가 천천히 떠오름(살아있는 배경, 단조로움 해소). 상태 없이 time 기반.
  void _motes(Canvas canvas, Size size, Color col) {
    if (size.width <= 0 || size.height <= 0) return;
    final p = Paint()..color = col;
    for (int i = 0; i < 18; i++) {
      final x = (i * 71.0 + sin(w.time * 0.4 + i) * 16) % size.width;
      final y = (i * 47.0 + w.time * (10 + (i % 4) * 6.0)) % size.height;
      canvas.drawCircle(Offset(x, size.height - y), 1.2 + (i % 3) * 0.8, p);
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
      case EType.swarm:
        base = const Color(0xFF6FB7C8);
        break;
      case EType.splitter:
        base = P.green;
        break;
      case EType.bomber:
        base = const Color(0xFFE8702E);
        break;
      case EType.shooter:
        base = const Color(0xFFD060C0);
        break;
      case EType.boss:
        base = const Color(0xFFFF4533);
        break;
      case EType.grunt:
        base = const Color(0xFF8A9BB0);
        break;
    }
    // 어두운 코어 + 네온 후광/링 (플레이어보다 어둡게 → 대비로 가독성)
    // 엘리트 — 금색 회전 후광 + 외곽 링(우선 처치 타겟으로 눈에 띄게)
    if (e.elite) {
      canvas.drawCircle(Offset(e.x, e.y), e.radius * 2.0, Paint()..color = P.gold.withOpacity(0.16));
      final a0 = w.time * 2.2;
      for (int i = 0; i < 3; i++) {
        final a = a0 + i * 2.094;
        canvas.drawCircle(Offset(e.x + cos(a) * (e.radius + 7), e.y + sin(a) * (e.radius + 7)), 2.6,
            Paint()..color = P.gold);
      }
    }
    // 성능: 외곽 후광 제거. 어두운 코어 + 네온 링 + 눈만(가독성 유지)
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
    final tp = _emoji(face, 18); // 이모지 캐시(매 프레임 layout 제거)
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));

    // 펫 말풍선 — 타이니가 직접 말함(상단 띄우기 대체). 긴 충신 대사도 줄바꿈 수용.
    if (w.petLineT > 0 && w.petLine.isNotEmpty) {
      final fa = (w.petLineT < 0.4 ? w.petLineT / 0.4 : 1.0).clamp(0.0, 1.0);
      const maxW = 168.0;
      final bt = TextPainter(
        text: TextSpan(
            text: w.petLine,
            style: TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: P.goldSoft.withOpacity(fa))),
        textDirection: TextDirection.ltr,
        maxLines: 4,
      )..layout(maxWidth: maxW);
      const pad = 7.0;
      final bw = bt.width + pad * 2;
      final bh = bt.height + pad * 2;
      double bx = x - bw / 2;
      double by = y - 18 - bh;
      final maxX = (w.w - bw - 4).clamp(4.0, 100000.0);
      bx = bx.clamp(4.0, maxX);
      if (by < 4) by = y + 18; // 위가 좁으면 아래로
      final rect =
          RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(9));
      canvas.drawRRect(rect, Paint()..color = const Color(0xFF140E09).withOpacity(0.82 * fa));
      canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = P.gold.withOpacity(0.85 * fa));
      bt.paint(canvas, Offset(bx + pad, by + pad));
    }
  }

  // 플레이어 — '호랑이가 되고 싶은 양'. 성장(tigerProg)에 따라 양→호랑이로 모핑.
  //  양: 폭신한 양털·둥근 귀·순한 눈 / 호랑이: 뾰족 귀·줄무늬 마스크·송곳니·사나운 눈매.
  void _player(Canvas canvas) {
    final hurt = w.contactCdView > 0;
    final p = w.tigerProg.clamp(0.0, 1.0); // 0=양, 1=완전한 호랑이
    const sheepCol = Color(0xFFF3ECDF); // 양털 크림색
    final col = hurt ? P.red : Color.lerp(sheepCol, w.skinColor, p)!; // 성장할수록 스킨색(호랑이)로
    final r = w.pr * w.growScale;
    final t = w.time;
    final moving = w.dirx != 0 || w.diry != 0;
    final bob = sin(t * (moving ? 10.0 : 3.0));
    final cx = w.px;
    final cy = w.py + bob * (moving ? 2.0 : 1.0);
    final sq = 1 + (moving ? bob * 0.10 : bob * 0.045);
    final fw = r * 2 / (1 + (sq - 1) * 0.5);
    final fh = r * 2 * sq;
    final stripeCol = const Color(0xFF3A2606);

    // 안광
    canvas.drawCircle(Offset(cx, cy), r * 3.0, Paint()..color = col.withOpacity(0.12));

    // 양털 — 머리 둘레의 폭신한 솜뭉치. 호랑이가 될수록 사라짐.
    if (p < 0.97) {
      final wool = Paint()..color = Color.lerp(Colors.white, sheepCol, 0.35)!.withOpacity((1 - p) * 0.95);
      for (int i = 0; i < 9; i++) {
        final a = i * 6.2831853 / 9 + t * 0.25;
        canvas.drawCircle(Offset(cx + cos(a) * r * 0.92, cy + sin(a) * r * 0.92),
            r * 0.46 * (1 - p * 0.55), wool);
      }
    }

    // 꼬리 (살랑)
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

    final earTwitch = sin(t * 2.3) * r * 0.08;
    // 양 귀 (둥글고 옆으로 처짐) — p가 낮을수록 진함
    if (p < 0.97) {
      final sp2 = Paint()..color = col.withOpacity(1 - p);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx - r * 0.95, cy - r * 0.3 + earTwitch), width: r * 0.7, height: r * 0.5),
          sp2);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx + r * 0.95, cy - r * 0.3 - earTwitch), width: r * 0.7, height: r * 0.5),
          sp2);
    }
    // 호랑이 귀 (뾰족) — p가 높을수록 진함
    if (p > 0.03) {
      final tp2 = Paint()..color = col.withOpacity(p);
      final ears = Path()
        ..moveTo(cx - r * 0.85, cy - r * 0.45)
        ..lineTo(cx - r * 0.45, cy - r * 1.2 - earTwitch)
        ..lineTo(cx - r * 0.05, cy - r * 0.6)
        ..close()
        ..moveTo(cx + r * 0.85, cy - r * 0.45)
        ..lineTo(cx + r * 0.45, cy - r * 1.2 + earTwitch)
        ..lineTo(cx + r * 0.05, cy - r * 0.6)
        ..close();
      canvas.drawPath(ears, tp2);
    }

    // 얼굴 (squash 타원)
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: fw * 1.7, height: fh * 1.7),
        Paint()..color = col.withOpacity(0.18));
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: fw, height: fh), Paint()..color = col);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: fw, height: fh),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withOpacity(0.85));

    // 호랑이 줄무늬 마스크 ('호랑이 탈') — 성장할수록 진해짐
    if (p > 0.05) {
      final st = Paint()
        ..color = stripeCol.withOpacity(p * 0.9)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(cx - r * 0.5, cy - r * 0.55), Offset(cx - r * 0.2, cy - r * 0.2), st);
      canvas.drawLine(Offset(cx + r * 0.5, cy - r * 0.55), Offset(cx + r * 0.2, cy - r * 0.2), st);
      canvas.drawLine(Offset(cx, cy - r * 0.72), Offset(cx, cy - r * 0.36), st); // 이마 중앙
      canvas.drawLine(Offset(cx - r * 0.72, cy + r * 0.08), Offset(cx - r * 0.42, cy + r * 0.14), st);
      canvas.drawLine(Offset(cx + r * 0.72, cy + r * 0.08), Offset(cx + r * 0.42, cy + r * 0.14), st);
    }

    // 볼터치(귀여움) — 호랑이가 되어도 약간 유지(무해+강함)
    final blush = Paint()..color = const Color(0xFFFF8E8E).withOpacity(0.5 * (1 - p * 0.5));
    canvas.drawCircle(Offset(cx - r * 0.55, cy + r * 0.28), r * 0.16, blush);
    canvas.drawCircle(Offset(cx + r * 0.55, cy + r * 0.28), r * 0.16, blush);

    // 눈
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
    // 사나운 눈매(호랑이) — 성장 시 눈썹이 짙어짐
    if (p > 0.3) {
      final browA = ((p - 0.3) * 1.4).clamp(0.0, 1.0);
      final brow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = stripeCol.withOpacity(browA);
      canvas.drawLine(Offset(cx - r * 0.56, ey - r * 0.34), Offset(cx - r * 0.22, ey - r * 0.16), brow);
      canvas.drawLine(Offset(cx + r * 0.56, ey - r * 0.34), Offset(cx + r * 0.22, ey - r * 0.16), brow);
    }
    // 코
    canvas.drawCircle(Offset(cx, cy + r * 0.32), r * 0.1, dark);
    // 송곳니(호랑이) — 성장할수록 또렷
    if (p > 0.4) {
      final fangA = ((p - 0.4) * 1.6).clamp(0.0, 1.0);
      final fang = Paint()..color = Colors.white.withOpacity(fangA);
      final ny = cy + r * 0.42;
      final f1 = Path()
        ..moveTo(cx - r * 0.18, ny)
        ..lineTo(cx - r * 0.06, ny)
        ..lineTo(cx - r * 0.12, ny + r * 0.24)
        ..close();
      final f2 = Path()
        ..moveTo(cx + r * 0.18, ny)
        ..lineTo(cx + r * 0.06, ny)
        ..lineTo(cx + r * 0.12, ny + r * 0.24)
        ..close();
      canvas.drawPath(f1, fang);
      canvas.drawPath(f2, fang);
    }
  }

  @override
  bool shouldRepaint(covariant WorldPainter old) => true;
}

// =============================================================================
//  초상화 진급 컷신 페인터 — 이전 → (화살표) → 새 초상화 비교 + 빛줄기·충격파
//  (다른 게임 진화/랭크업 UI 참조: before→after + arrow)
// =============================================================================
class MorphPainter extends CustomPainter {
  final World w;
  MorphPainter(this.w);

  @override
  void paint(Canvas canvas, Size size) {
    final t = w.morphClock;
    final cy = size.height * 0.40;
    final R = min(size.width, size.height) * 0.13;
    final cxL = size.width * 0.27, cxR = size.width * 0.73;
    final fromProg = kPortraits[w.morphFromTier.clamp(0, kPortraits.length - 1)].prog;
    final newProg = w.tigerProg;
    // 오른쪽(새) 등장 스케일 — 짜잔 팝
    final pop = t < 0.32 ? (t / 0.32) * 1.15 : (1.0 + sin((t - 0.32) * 5) * 0.05);

    // 새 초상화 주변 회전 빛줄기
    final rayLen = R * (1.3 + sin(t * 4) * 0.25);
    final rayPaint = Paint()
      ..color = P.gold.withOpacity(0.10 + 0.10 * (0.5 + 0.5 * sin(t * 6)))
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 18; i++) {
      final a = t * 1.4 + i * 6.2831853 / 18;
      final i0 = R * 1.0;
      canvas.drawLine(Offset(cxR + cos(a) * i0, cy + sin(a) * i0),
          Offset(cxR + cos(a) * (i0 + rayLen), cy + sin(a) * (i0 + rayLen)), rayPaint);
    }
    // 확산 충격파 링(새 쪽)
    for (int k = 0; k < 3; k++) {
      final rt = t - 0.32 - k * 0.16;
      if (rt > 0 && rt < 1.0) {
        canvas.drawCircle(
            Offset(cxR, cy),
            rt * size.width * 0.4,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5 * (1 - rt)
              ..color = (k == 1 ? P.blood : P.gold).withOpacity(0.5 * (1 - rt)));
      }
    }

    // 이전 초상화 (왼쪽, 어둡게·작게·고정)
    _avatar(canvas, cxL, cy, R * 0.82, fromProg, t, 0.45);
    // 새 초상화 (오른쪽, 밝게·팝)
    _avatar(canvas, cxR, cy, R * pop.clamp(0.0, 1.25), newProg, t, 1.0);

    // 화살표 (이전 → 새), 등장 후 펄스
    if (t > 0.25) {
      final ax0 = cxL + R * 1.05, ax1 = cxR - R * 1.15;
      if (ax1 > ax0) {
        final pulse = 0.6 + 0.4 * (0.5 + 0.5 * sin(t * 8));
        final ap = Paint()
          ..color = P.gold.withOpacity(pulse)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(ax0, cy), Offset(ax1, cy), ap);
        canvas.drawLine(Offset(ax1, cy), Offset(ax1 - 13, cy - 10), ap);
        canvas.drawLine(Offset(ax1, cy), Offset(ax1 - 13, cy + 10), ap);
      }
    }
  }

  // 초상화 아바타 1개 그리기 (tg=외형, a=알파)
  void _avatar(Canvas canvas, double cx, double cy, double r, double tg, double t, double a) {
    if (r < 1) return;
    const sheepCol = Color(0xFFF3ECDF);
    final col0 = Color.lerp(sheepCol, P.gold, tg)!;
    final col = col0.withOpacity(a);
    const stripe = Color(0xFF3A2606);
    // 안광
    canvas.drawCircle(Offset(cx, cy), r * 1.9, Paint()..color = P.gold.withOpacity((0.10 + 0.12 * tg) * a));
    // 양털
    if (tg < 0.95) {
      final wool = Paint()..color = Colors.white.withOpacity((1 - tg) * 0.8 * a);
      for (int i = 0; i < 10; i++) {
        final ang = i * 6.2831853 / 10 + t * 0.6;
        canvas.drawCircle(Offset(cx + cos(ang) * r * 0.95, cy + sin(ang) * r * 0.95),
            r * 0.42 * (1 - tg * 0.5), wool);
      }
    }
    // 양 귀
    if (tg < 0.95) {
      final sp = Paint()..color = col0.withOpacity((1 - tg) * a);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - r * 0.95, cy - r * 0.35), width: r * 0.7, height: r * 0.5), sp);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + r * 0.95, cy - r * 0.35), width: r * 0.7, height: r * 0.5), sp);
    }
    // 호랑이 귀
    if (tg > 0.05) {
      final tp = Paint()..color = col0.withOpacity(tg * a);
      final ears = Path()
        ..moveTo(cx - r * 0.85, cy - r * 0.45)
        ..lineTo(cx - r * 0.45, cy - r * 1.25)
        ..lineTo(cx - r * 0.05, cy - r * 0.6)
        ..close()
        ..moveTo(cx + r * 0.85, cy - r * 0.45)
        ..lineTo(cx + r * 0.45, cy - r * 1.25)
        ..lineTo(cx + r * 0.05, cy - r * 0.6)
        ..close();
      canvas.drawPath(ears, tp);
    }
    // 얼굴
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = col);
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white.withOpacity(0.85 * a));
    // 줄무늬
    if (tg > 0.05) {
      final st = Paint()
        ..color = stripe.withOpacity(tg * 0.9 * a)
        ..strokeWidth = r * 0.09
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(cx - r * 0.5, cy - r * 0.55), Offset(cx - r * 0.2, cy - r * 0.2), st);
      canvas.drawLine(Offset(cx + r * 0.5, cy - r * 0.55), Offset(cx + r * 0.2, cy - r * 0.2), st);
      canvas.drawLine(Offset(cx, cy - r * 0.72), Offset(cx, cy - r * 0.36), st);
    }
    // 눈
    final dark = Paint()..color = const Color(0xFF160F06).withOpacity(a);
    final ey = cy - r * 0.05;
    canvas.drawCircle(Offset(cx - r * 0.38, ey), r * 0.2, dark);
    canvas.drawCircle(Offset(cx + r * 0.38, ey), r * 0.2, dark);
    final hi = Paint()..color = Colors.white.withOpacity(0.9 * a);
    canvas.drawCircle(Offset(cx - r * 0.42, ey - r * 0.07), r * 0.07, hi);
    canvas.drawCircle(Offset(cx + r * 0.34, ey - r * 0.07), r * 0.07, hi);
    // 사나운 눈썹
    if (tg > 0.2) {
      final brow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..strokeCap = StrokeCap.round
        ..color = stripe.withOpacity(tg * a);
      canvas.drawLine(Offset(cx - r * 0.56, ey - r * 0.34), Offset(cx - r * 0.22, ey - r * 0.16), brow);
      canvas.drawLine(Offset(cx + r * 0.56, ey - r * 0.34), Offset(cx + r * 0.22, ey - r * 0.16), brow);
    }
    // 코
    canvas.drawCircle(Offset(cx, cy + r * 0.32), r * 0.1, dark);
    // 송곳니
    if (tg > 0.3) {
      final fang = Paint()..color = Colors.white.withOpacity((((tg - 0.3) * 1.5).clamp(0.0, 1.0)) * a);
      final ny = cy + r * 0.42;
      final f1 = Path()
        ..moveTo(cx - r * 0.18, ny)
        ..lineTo(cx - r * 0.06, ny)
        ..lineTo(cx - r * 0.12, ny + r * 0.26)
        ..close();
      final f2 = Path()
        ..moveTo(cx + r * 0.18, ny)
        ..lineTo(cx + r * 0.06, ny)
        ..lineTo(cx + r * 0.12, ny + r * 0.26)
        ..close();
      canvas.drawPath(f1, fang);
      canvas.drawPath(f2, fang);
    }
  }

  @override
  bool shouldRepaint(covariant MorphPainter old) => true;
}
