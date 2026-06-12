// =============================================================================
//  프로젝트 어흥 : REBORN
//  - Reigns식 스와이프 카드 + 미터 생존 코어 (모바일 최적, 텍스트 최소)
//  - 에셋 0개. 모든 그래픽은 CustomPainter/파티클로 코드 생성.
//  - 주사위(D20)·스탯 보정·숨은 연패보호(pity)·회차 기록 등 검증된 개념 계승.
//  ⚠ 빌드: Flutter 3.24.5 — 색 투명도는 반드시 color.withOpacity(x). (withValues 금지)
// =============================================================================
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const RebornApp());

// =============================================================================
//  팔레트
// =============================================================================
class P {
  const P._();
  static const bg = Color(0xFF0E0B09);
  static const bg2 = Color(0xFF1A1410);
  static const panel = Color(0xFF211913);
  static const line = Color(0xFF3A2F28);
  static const gold = Color(0xFFE8A33D);
  static const goldSoft = Color(0xFFF3D89A);
  static const blood = Color(0xFFB7402E);
  static const green = Color(0xFF81C784);
  static const red = Color(0xFFE57373);
  static const parch = Color(0xFFF0E6DC);
  static const muted = Color(0xFF9C8C7E);
}

// =============================================================================
//  미터 — 4종, 양극단(0/100) 모두 죽음 (Reigns식 균형 긴장)
// =============================================================================
enum Meter { wild, infl, hide, cred }

class MeterInfo {
  final String label, icon, lowDeath, highDeath;
  final Color color;
  const MeterInfo(this.label, this.icon, this.color, this.lowDeath, this.highDeath);
}

const Map<Meter, MeterInfo> kMeters = {
  Meter.wild: MeterInfo('야성', '🐅', Color(0xFFE57373),
      '겁에 질린 부족이 대장을 버리고 흩어졌습니다.', '광기가 대장을 집어삼켜 제 무리마저 물어뜯었습니다.'),
  Meter.infl: MeterInfo('영향력', '👑', Color(0xFFBA8FE0),
      '누구도 대장을 따르지 않습니다. 부족은 연기처럼 흩어졌습니다.', '너무 커진 이름. 의회의 자객이 끝내 목을 거뒀습니다.'),
  Meter.hide: MeterInfo('가죽', '🛡', Color(0xFF7FB7C9),
      '무방비의 둥지가 첫 습격에 잿더미가 됐습니다.', '겹겹의 가죽에 짓눌려 굼떠진 부족이 도태됐습니다.'),
  Meter.cred: MeterInfo('경계', '⚖', Color(0xFFD7B86A),
      '빚쟁이들이 둥지를 뜯어갔습니다. 남은 건 뼈뿐입니다.', '의회의 금화에 길들여져, 대장은 그들의 꼭두각시가 됐습니다.'),
};

// =============================================================================
//  씬 엠블럼 종류 (CustomPainter가 코드로 그림)
// =============================================================================
enum Scene { tiger, wolf, eye, coin, throne, skull, snake, fire, hunter, totem }

// =============================================================================
//  선택지 / 카드
// =============================================================================
class Choice {
  final String label; // 짧게
  final Map<Meter, int> fx;
  final int mana;
  final String result; // 한 줄 결과
  // 주사위 도박: roll != null이면 D20 판정. 성공=fx/result, 실패=failFx/failResult
  final Meter? roll;
  final int dc;
  final Map<Meter, int> failFx;
  final int failMana;
  final String failResult;
  final String? setFlag;
  const Choice(
    this.label, {
    this.fx = const {},
    this.mana = 0,
    this.result = '',
    this.roll,
    this.dc = 12,
    this.failFx = const {},
    this.failMana = 0,
    this.failResult = '',
    this.setFlag,
  });
}

class CardDef {
  final String id;
  final Scene scene;
  final String speaker; // 누가 말하나
  final String text; // 한 줄 상황
  final Choice left; // ← 스와이프
  final Choice right; // → 스와이프
  final int minTurn;
  final String? requireFlag;
  final bool once;
  const CardDef(this.id, this.scene, this.speaker, this.text, this.left, this.right,
      {this.minTurn = 0, this.requireFlag, this.once = false});
}

// =============================================================================
//  카드 덱 — 한 문장 원칙, 가혹한 결과 (확장은 여기 항목만 추가하면 자동 반영)
// =============================================================================
const List<CardDef> kDeck = [
  CardDef('tax', Scene.eye, '의회 징세관',
      '"이번 달 피의 조공이 비었군. 어쩔 텐가, 들짐승?"',
      Choice('이빨을 드러낸다',
          roll: Meter.wild, dc: 12,
          fx: {Meter.wild: 6, Meter.cred: -8}, mana: 9000,
          result: '징세관의 멱살을 잡아 던졌습니다. 무리가 환호합니다.',
          failFx: {Meter.wild: -6, Meter.cred: -10}, failMana: -6000,
          failResult: '되레 제압당해 곳간을 털렸습니다.'),
      Choice('빚을 내어 바친다',
          fx: {Meter.cred: 10, Meter.infl: 4}, mana: -7000,
          result: '굽신거리며 조공을 채웠습니다. 의회가 흡족해합니다.')),
  CardDef('smuggler', Scene.coin, '암시장 밀매꾼',
      '"싸게 넘기지… 출처는 묻지 마쇼, 대장."',
      Choice('회유해 사들인다',
          fx: {Meter.cred: -6, Meter.hide: 6}, mana: -5000,
          result: '수상한 병기를 손에 넣었습니다. 둥지가 단단해집니다.'),
      Choice('밀고하고 내쫓는다',
          fx: {Meter.infl: 7, Meter.cred: 5}, mana: 2000,
          result: '의회에 점수를 땄지만 뒷골목이 등을 돌립니다.')),
  CardDef('dogs', Scene.wolf, '떠돌이 들개 무리',
      '굶주린 들개 떼가 둥지의 경계를 어슬렁댑니다.',
      Choice('정면으로 약탈',
          roll: Meter.wild, dc: 13,
          fx: {Meter.wild: 8}, mana: 12000,
          result: '단숨에 짓밟고 전리품을 쓸어담았습니다.',
          failFx: {Meter.wild: -5, Meter.hide: -6}, failMana: -4000,
          failResult: '역으로 물어뜯겨 부상병만 늘었습니다.'),
      Choice('가죽 뒤에 숨어 버틴다',
          fx: {Meter.hide: 8, Meter.wild: -4},
          result: '문을 걸어 잠그고 버텼습니다. 무리가 답답해합니다.')),
  CardDef('shaman', Scene.totem, '늙은 무당',
      '"운명의 뼈를 던져드리리다… 대가는 피 한 줌."',
      Choice('운명에 건다',
          roll: Meter.infl, dc: 14,
          fx: {Meter.infl: 8, Meter.wild: 5}, mana: 8000,
          result: '뼈가 길조를 가리켰습니다. 기세가 치솟습니다.',
          failFx: {Meter.infl: -7}, failMana: -3000,
          failResult: '흉조였습니다. 부족이 불안에 떱니다.'),
      Choice('미신이라며 쫓아낸다',
          fx: {Meter.cred: 5, Meter.infl: -4},
          result: '현실주의자라 칭송받았지만 노인은 저주를 남겼습니다.')),
  CardDef('feast', Scene.fire, '타이니',
      '"대장님! 약탈한 고기가 산더미입니다. 잔치를 벌일까요?"',
      Choice('성대하게 잔치',
          fx: {Meter.wild: 7, Meter.infl: 6, Meter.hide: -4}, mana: -4000,
          result: '무리의 충성이 불타오릅니다. 다만 곳간이 비었습니다.'),
      Choice('아껴 비축한다',
          fx: {Meter.hide: 6, Meter.wild: -3}, mana: 3000,
          result: '겨울을 대비했지만 무리는 시무룩합니다.')),
  CardDef('rival', Scene.tiger, '경쟁 부족장',
      '"네 자리, 내가 가져가지." 라이벌 맹수가 으르렁댑니다.',
      Choice('결투를 받는다',
          roll: Meter.wild, dc: 15,
          fx: {Meter.wild: 10, Meter.infl: 8}, mana: 15000,
          result: '송곳니로 끝장냈습니다. 대륙이 이름을 떱니다.',
          failFx: {Meter.wild: -8, Meter.infl: -6}, failMana: -8000,
          failResult: '패배해 영역 절반을 빼앗겼습니다.'),
      Choice('동맹을 제안한다',
          fx: {Meter.infl: 7, Meter.cred: 4, Meter.wild: -5},
          result: '피를 섞어 동맹했습니다. 사나운 자들은 비겁하다 수군댑니다.')),
  CardDef('council2', Scene.eye, '그림자 의회',
      '"흥미롭군. 우리 편에 서면… 황금이 끝없을 텐데?"',
      Choice('손을 잡는다',
          fx: {Meter.cred: 12, Meter.wild: -8}, mana: 14000,
          result: '의회의 금화가 쏟아집니다. 야성이 무뎌집니다.'),
      Choice('침을 뱉는다',
          fx: {Meter.wild: 9, Meter.cred: -10, Meter.infl: 5},
          result: '의회의 면전에 선전포고했습니다. 무리가 열광합니다.',
          setFlag: 'defiant')),
  CardDef('plague', Scene.skull, '역병',
      '둥지에 검은 기침이 번집니다. 약한 자부터 쓰러집니다.',
      Choice('약한 자를 버린다',
          fx: {Meter.wild: 5, Meter.infl: -8, Meter.hide: 6},
          result: '냉혹하게 격리했습니다. 무리가 두려워하면서도 살아남습니다.'),
      Choice('끝까지 돌본다',
          roll: Meter.hide, dc: 13,
          fx: {Meter.infl: 9, Meter.hide: 4},
          result: '한 명도 잃지 않았습니다. 충성이 깊어집니다.',
          failFx: {Meter.infl: -5, Meter.hide: -6}, failMana: -3000,
          failResult: '역병이 번져 둥지가 휘청였습니다.')),
  CardDef('spy', Scene.hunter, '그림자 사냥꾼',
      '복면의 자객이 밤그늘에서 거래를 제안합니다.',
      Choice('정보를 산다',
          fx: {Meter.infl: 6, Meter.cred: -5}, mana: -4000,
          result: '의회의 약점을 손에 넣었습니다.', setFlag: 'intel'),
      Choice('목을 노린다',
          roll: Meter.wild, dc: 16,
          fx: {Meter.wild: 9, Meter.hide: 5}, mana: 6000,
          result: '자객을 거꾸로 사냥했습니다. 소문이 대장을 키웁니다.',
          failFx: {Meter.wild: -6, Meter.hide: -7},
          failResult: '놓쳤습니다. 둥지의 위치가 새어나갔습니다.')),
  CardDef('snakeoil', Scene.snake, '교활한 상인',
      '"신기루 같은 투자처가 있소… 권세가 두 배요!"',
      Choice('전부 건다',
          roll: Meter.cred, dc: 15,
          fx: {Meter.cred: 4}, mana: 20000,
          result: '신기루가 진짜였습니다! 곳간이 넘칩니다.',
          failFx: {Meter.cred: -8}, failMana: -15000,
          failResult: '거품이 터졌습니다. 권세가 와해됐습니다.'),
      Choice('코웃음 친다',
          fx: {Meter.cred: 6, Meter.infl: 3},
          result: '신기루를 꿰뚫어 봤습니다. 침착함이 신뢰를 낳습니다.')),
  CardDef('cubs', Scene.tiger, '타이니',
      '"대장님 핏줄을 이은 새끼 맹수들이 태어났습니다!"',
      Choice('전사로 키운다',
          fx: {Meter.wild: 8, Meter.hide: -3},
          result: '어린 송곳니들이 사납게 자랍니다.'),
      Choice('지혜를 가르친다',
          fx: {Meter.infl: 7, Meter.cred: 4, Meter.wild: -4},
          result: '영민한 후계가 자랍니다. 부족의 미래가 밝습니다.')),
  CardDef('debt', Scene.coin, '빚받이',
      '"피의 조공이 밀렸다. 살점으로라도 받아내지."',
      Choice('한 판 더 빌린다',
          fx: {Meter.cred: -10}, mana: 10000,
          result: '눈덩이 빚을 졌습니다. 당장은 숨통이 트입니다.'),
      Choice('가진 걸 털어 갚는다',
          fx: {Meter.cred: 12, Meter.hide: -4}, mana: -9000,
          result: '빚을 청산했습니다. 곳간은 비었지만 경계가 회복됩니다.')),
  CardDef('beast', Scene.wolf, '평원의 괴수',
      '거대한 괴수가 영토 한복판에 둥지를 틀었습니다.',
      Choice('무리를 몰아 사냥',
          roll: Meter.wild, dc: 16,
          fx: {Meter.wild: 9, Meter.infl: 7}, mana: 18000,
          result: '괴수를 쓰러뜨렸습니다. 그 가죽이 전설이 됩니다.',
          failFx: {Meter.wild: -7, Meter.hide: -8}, failMana: -9000,
          failResult: '많은 송곳니를 잃었습니다.'),
      Choice('영토를 양보한다',
          fx: {Meter.hide: 6, Meter.infl: -6},
          result: '충돌을 피했습니다. 무리는 비겁하다 여깁니다.')),
  CardDef('oracle', Scene.eye, '의회 내부자', // intel 체인
      '"내가 흘린 약점… 지금이 의회를 칠 때요." (정보 보유)',
      Choice('급습한다',
          roll: Meter.infl, dc: 14,
          fx: {Meter.infl: 12, Meter.cred: -6}, mana: 16000,
          result: '약점을 찔러 의회 금고를 털었습니다!',
          failFx: {Meter.infl: -8, Meter.cred: -8}, failMana: -6000,
          failResult: '함정이었습니다. 호되게 당했습니다.'),
      Choice('때를 기다린다',
          fx: {Meter.cred: 6, Meter.hide: 5},
          result: '칼을 갈며 기다립니다.'),
      requireFlag: 'intel', once: true),
  CardDef('uprising', Scene.fire, '성난 무리', // defiant 체인
      '"의회에 맞서기로 한 이상, 끝까지 갑시다!" 무리가 들끓습니다.',
      Choice('봉기를 이끈다',
          roll: Meter.wild, dc: 15,
          fx: {Meter.wild: 12, Meter.infl: 10}, mana: 8000,
          result: '대장이 앞장서 봉기가 대륙을 흔듭니다.',
          failFx: {Meter.wild: -8, Meter.infl: -8},
          failResult: '봉기가 진압당해 피로 물들었습니다.'),
      Choice('숨을 고른다',
          fx: {Meter.hide: 8, Meter.cred: 4, Meter.infl: -4},
          result: '한 발 물러나 전열을 가다듬습니다.'),
      requireFlag: 'defiant', once: true),
  CardDef('drought', Scene.skull, '가뭄',
      '대지가 갈라지고 사냥감이 자취를 감췄습니다.',
      Choice('이웃을 약탈한다',
          fx: {Meter.wild: 6, Meter.infl: -5, Meter.cred: -4}, mana: 9000,
          result: '약한 부족을 털어 버텼습니다. 원성이 자자합니다.'),
      Choice('비축분을 푼다',
          fx: {Meter.infl: 7, Meter.hide: -5}, mana: -5000,
          result: '곳간을 풀어 무리를 먹였습니다. 충성이 깊어집니다.')),
  CardDef('idol', Scene.totem, '타이니',
      '"폐허에서 황금 우상을 찾았습니다! …근데 저주받았다는 소문이…"',
      Choice('차지한다',
          roll: Meter.cred, dc: 13,
          fx: {Meter.infl: 8}, mana: 13000,
          result: '저주는 헛소문이었습니다. 우상이 권위를 드높입니다.',
          failFx: {Meter.cred: -7, Meter.hide: -5},
          failResult: '재앙이 잇따릅니다. 우상을 내다 버렸습니다.'),
      Choice('땅에 묻는다',
          fx: {Meter.cred: 6},
          result: '화근을 묻었습니다. 신중함이 빛납니다.')),
  CardDef('marriage', Scene.tiger, '먼 부족의 사절',
      '"우리 족장의 자식과 혼인하면, 두 부족이 하나가 되오."',
      Choice('받아들인다',
          fx: {Meter.infl: 9, Meter.cred: 5, Meter.wild: -4},
          result: '동맹 혼인으로 세력이 커집니다.'),
      Choice('거절한다',
          fx: {Meter.wild: 6, Meter.infl: -4},
          result: '홀로 선다 선언했습니다. 사절이 모욕감에 떠납니다.')),
  CardDef('storm', Scene.fire, '대붕괴',
      '하늘이 무너지듯 시장이 와해됩니다. 모두가 곳간을 움켜쥡니다.',
      Choice('헐값에 쓸어담는다',
          roll: Meter.cred, dc: 14,
          fx: {Meter.cred: 6}, mana: 17000,
          result: '바닥에서 주워담아 권세를 불렸습니다.',
          failFx: {Meter.cred: -8}, failMana: -10000,
          failResult: '같이 휩쓸려 곳간이 텅 비었습니다.'),
      Choice('가죽을 두껍게 한다',
          fx: {Meter.hide: 9, Meter.wild: -3},
          result: '폭풍을 버텨냈습니다.'),
      minTurn: 4),
  CardDef('traitor', Scene.hunter, '배신의 그림자',
      '믿었던 부관이 의회와 내통한 정황이 잡혔습니다.',
      Choice('본보기로 처단',
          fx: {Meter.wild: 7, Meter.cred: 5, Meter.infl: -5},
          result: '피의 본보기를 세웠습니다. 모두가 입을 다뭅니다.'),
      Choice('회유해 첩자로',
          roll: Meter.infl, dc: 15,
          fx: {Meter.infl: 9, Meter.cred: 4}, mana: 4000,
          result: '돌려세워 이중첩자로 만들었습니다.',
          failFx: {Meter.infl: -8, Meter.hide: -6},
          failResult: '되레 둥지의 비밀이 통째로 새어나갔습니다.'),
      minTurn: 5),
];

// =============================================================================
//  엔진 — Reigns식 미터 생존 + D20 판정 + 숨은 연패보호
// =============================================================================
enum Phase { opening, playing, result, dead, clear }

class Game extends ChangeNotifier {
  final Random _rng = Random();
  static const int goalTurn = 16; // 이 턴을 넘기면 흑요석 왕좌(최종 카드)
  static const int meterStart = 50;

  Map<Meter, int> meters = {};
  int mana = 12000; // 전리품(권세 자금) — 0 밑으로 깊이 빠지면 몰락
  int turn = 1;
  int streak = 0; // 연승(판정 성공 연쇄)
  int _failStreak = 0; // 숨은 연패보호
  Set<String> flags = {};
  Set<String> used = {};
  String _lastId = '';
  List<String> log = [];

  Phase phase = Phase.opening;
  CardDef? card;
  bool tinySilenced = false;

  // 결과 표시용
  String resultText = '';
  bool resultGood = true;
  int? lastRoll; // 주사위 눈 (있으면 표시)
  bool lastCrit = false;
  Map<Meter, int> lastFx = {};
  int lastMana = 0;

  // 죽음/승리
  String endReason = '';

  // 영구 기록
  int bestTurn = 0;
  int totalRuns = 0;

  Game() {
    _loadRecords();
    _restoreOrNew();
  }

  int meterMod(Meter m) => ((meters[m]! - 50) / 12).round();

  // ── 새 게임 / 복원 ──
  void _freshRun() {
    meters = {for (final m in Meter.values) m: meterStart};
    mana = 12000;
    turn = 1;
    streak = 0;
    _failStreak = 0;
    flags = {};
    used = {};
    _lastId = '';
    log = [];
    endReason = '';
    phase = Phase.opening;
    card = null;
  }

  void startAfterOpening() {
    if (phase == Phase.opening) {
      _next();
    }
  }

  void newGame() {
    _freshRun();
    _next();
    _save();
    notifyListeners();
  }

  // ── 카드 선택 ──
  void _next() {
    if (turn > goalTurn) {
      // 흑요석 왕좌는 쓰러질 때까지 매 턴 다시 일어선다(승리=clear만이 탈출구).
      card = _throneCard();
      phase = Phase.playing;
      _save();
      notifyListeners();
      return;
    }
    final pool = kDeck.where((c) {
      if (c.id == _lastId) return false;
      if (c.minTurn > turn) return false;
      if (c.requireFlag != null && !flags.contains(c.requireFlag)) return false;
      if (c.once && used.contains(c.id)) return false;
      return true;
    }).toList();
    final list = pool.isNotEmpty
        ? pool
        : kDeck.where((c) => c.id != _lastId && c.requireFlag == null).toList();
    card = list[_rng.nextInt(list.length)];
    phase = Phase.playing;
    _save();
    notifyListeners();
  }

  CardDef _throneCard() => const CardDef(
        'THRONE',
        Scene.throne,
        '흑요석 왕좌',
        '의장 네오 맹수가 옥좌에서 일어섭니다. "감히 시스템의 주인을 거역하느냐?"',
        Choice('송곳니로 끝장낸다',
            roll: Meter.wild,
            dc: 17,
            fx: {Meter.wild: 5, Meter.infl: 5},
            mana: 50000,
            result: '의장의 목을 물어뜯었습니다. 대륙은 이제 대장의 것입니다.',
            failFx: {Meter.wild: -40},
            failResult: '한 끗이 모자랐습니다. 옥좌가 대장을 집어삼킵니다.'),
        Choice('영향력으로 무너뜨린다',
            roll: Meter.infl,
            dc: 17,
            fx: {Meter.infl: 5, Meter.cred: 5},
            mana: 50000,
            result: '의회가 등을 돌렸습니다. 의장은 홀로 무너졌습니다.',
            failFx: {Meter.infl: -40},
            failResult: '의회는 끝내 의장의 편이었습니다. 모든 게 끝났습니다.'),
      );

  // ── 선택 실행 ──
  void choose(bool right) {
    if (phase != Phase.playing || card == null) return;
    final c = card!;
    final ch = right ? c.right : c.left;
    _haptic(light: true);

    bool success = true;
    lastRoll = null;
    lastCrit = false;
    if (ch.roll != null) {
      final raw = 1 + _rng.nextInt(20);
      final pity = (_failStreak * 1).clamp(0, 4);
      final total = raw + meterMod(ch.roll!) + pity;
      if (raw == 1) {
        success = false;
      } else if (raw == 20) {
        success = true;
        lastCrit = true;
      } else {
        success = total >= ch.dc;
      }
      lastRoll = raw;
      _failStreak = success ? 0 : _failStreak + 1;
    }

    final fx = success ? ch.fx : ch.failFx;
    final manaD = success ? ch.mana : ch.failMana;
    resultText = success ? ch.result : ch.failResult;
    resultGood = success;
    lastFx = fx;
    lastMana = manaD;

    fx.forEach((m, d) {
      meters[m] = (meters[m]! + d).clamp(0, 100);
    });
    mana += manaD;
    if (success && ch.roll != null) {
      streak += 1;
    } else if (!success) {
      streak = 0;
    }
    if (ch.setFlag != null) flags.add(ch.setFlag!);
    if (c.once) used.add(c.id);
    _lastId = c.id;

    // 로그 기록
    final emoji = success ? '✔' : '✘';
    log.insert(0, '$emoji [${turn}턴] ${c.speaker}: ${ch.label} — $resultText');
    if (log.length > 40) log.removeLast();

    // 사망/승리 판정
    final death = _deathCheck();
    if (death != null) {
      endReason = death;
      phase = Phase.dead;
      _onRunEnd();
      _haptic(heavy: true);
    } else if (c.id == 'THRONE' && success) {
      endReason = resultText;
      phase = Phase.clear;
      _onRunEnd();
      _haptic(heavy: true);
    } else {
      phase = Phase.result;
      if (lastCrit || (success && manaD >= 14000)) _haptic(heavy: true);
    }
    _save();
    notifyListeners();
  }

  // 결과 카드 → 다음 카드
  void advance() {
    if (phase != Phase.result) return;
    turn += 1;
    _next();
  }

  String? _deathCheck() {
    for (final m in Meter.values) {
      final v = meters[m]!;
      if (v <= 0) return kMeters[m]!.lowDeath;
      if (v >= 100) return kMeters[m]!.highDeath;
    }
    if (mana <= -20000) return '금고가 바닥나 부족이 뿔뿔이 흩어졌습니다. (몰락)';
    return null;
  }

  void _onRunEnd() {
    totalRuns += 1;
    if (turn > bestTurn) bestTurn = turn;
    _saveRecords();
    html.window.localStorage.remove('reborn_run');
  }

  void restart() {
    _freshRun();
    phase = Phase.opening; // 오프닝은 1회만 보고 싶다면 skip; 여기선 바로 시작
    _next();
    _save();
    notifyListeners();
  }

  void toggleTiny() {
    tinySilenced = !tinySilenced;
    notifyListeners();
  }

  // ── 저장/복원 ──
  void _save() {
    if (phase == Phase.dead || phase == Phase.clear) return;
    try {
      html.window.localStorage['reborn_run'] = jsonEncode({
        'm': {for (final e in meters.entries) e.key.index.toString(): e.value},
        'mana': mana,
        'turn': turn,
        'streak': streak,
        'fs': _failStreak,
        'flags': flags.toList(),
        'used': used.toList(),
        'last': _lastId,
        'log': log,
        'card': card?.id,
      });
    } catch (_) {}
  }

  void _restoreOrNew() {
    final raw = html.window.localStorage['reborn_run'];
    if (raw == null) {
      _freshRun();
      return;
    }
    try {
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      meters = {
        for (final m in Meter.values)
          m: ((j['m'] as Map)[m.index.toString()] as int?) ?? meterStart
      };
      mana = j['mana'] as int? ?? 12000;
      turn = j['turn'] as int? ?? 1;
      streak = j['streak'] as int? ?? 0;
      _failStreak = j['fs'] as int? ?? 0;
      flags = ((j['flags'] as List?) ?? []).map((e) => e as String).toSet();
      used = ((j['used'] as List?) ?? []).map((e) => e as String).toSet();
      _lastId = j['last'] as String? ?? '';
      log = ((j['log'] as List?) ?? []).map((e) => e as String).toList();
      final cid = j['card'] as String?;
      card = cid == 'THRONE'
          ? _throneCard()
          : (cid == null ? null : kDeck.firstWhere((c) => c.id == cid, orElse: () => kDeck.first));
      // 진행 중이던 런이 있으면 오프닝 건너뛰고 바로 플레이
      phase = card == null ? Phase.opening : Phase.playing;
    } catch (_) {
      _freshRun();
    }
  }

  void _loadRecords() {
    try {
      final raw = html.window.localStorage['reborn_rec'];
      if (raw == null) return;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      bestTurn = j['best'] as int? ?? 0;
      totalRuns = j['runs'] as int? ?? 0;
    } catch (_) {}
  }

  void _saveRecords() {
    try {
      html.window.localStorage['reborn_rec'] =
          jsonEncode({'best': bestTurn, 'runs': totalRuns});
    } catch (_) {}
  }

  void _haptic({bool light = false, bool heavy = false}) {
    try {
      if (heavy) {
        HapticFeedback.heavyImpact();
      } else if (light) {
        HapticFeedback.selectionClick();
      }
    } catch (_) {}
  }
}

// =============================================================================
//  앱 루트
// =============================================================================
class RebornApp extends StatelessWidget {
  const RebornApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '어흥 REBORN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: P.bg,
        fontFamily: 'sans-serif',
        useMaterial3: false,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final Game g = Game();
  double _drag = 0; // 현재 스와이프 양 (-1..1 정규화)
  bool _logOpen = false;

  @override
  void initState() {
    super.initState();
    g.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    g.removeListener(_onChange);
    g.dispose();
    super.dispose();
  }

  // 드래그 방향에 따라 강조될 미터 fx (Reigns식 미리보기)
  Map<Meter, int> get _previewFx {
    if (g.phase != Phase.playing || g.card == null || _drag.abs() < 0.12) {
      return const {};
    }
    final ch = _drag > 0 ? g.card!.right : g.card!.left;
    return ch.fx;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Stack(children: [
              const Positioned.fill(child: LivingBackground()),
              _content(),
              if (g.phase == Phase.opening)
                Opening(onDone: () => g.startAfterOpening()),
              if (_logOpen) _chronicle(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (g.phase) {
      case Phase.dead:
        return EndScreen(g: g, victory: false);
      case Phase.clear:
        return EndScreen(g: g, victory: true);
      case Phase.opening:
        return const SizedBox.shrink();
      default:
        return Column(children: [
          MeterHud(g: g, preview: _previewFx, onLog: () => setState(() => _logOpen = true)),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: g.phase == Phase.result
                  ? ResultView(g: g, key: const ValueKey('result'))
                  : SwipeStage(
                      key: ValueKey('card_${g.card?.id}_${g.turn}'),
                      g: g,
                      onDrag: (d) => setState(() => _drag = d),
                      onSettle: () => setState(() => _drag = 0),
                    ),
            ),
          ),
        ]);
    }
  }

  Widget _chronicle() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _logOpen = false),
        child: Container(
          color: Colors.black.withOpacity(0.6),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: const BoxDecoration(
                color: P.bg2,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: P.gold, width: 2)),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: Row(children: [
                    const Text('📜 전장 일지',
                        style: TextStyle(
                            color: P.gold, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                        onPressed: () => setState(() => _logOpen = false),
                        icon: const Icon(Icons.close, color: P.muted)),
                  ]),
                ),
                const Divider(height: 1, color: P.line),
                Expanded(
                  child: g.log.isEmpty
                      ? const Center(
                          child: Text('아직 기록된 사건이 없습니다.',
                              style: TextStyle(color: P.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(14),
                          itemCount: g.log.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(g.log[i],
                                style: const TextStyle(
                                    color: P.parch, fontSize: 12.5, height: 1.4)),
                          ),
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  상단 미터 HUD
// =============================================================================
class MeterHud extends StatelessWidget {
  final Game g;
  final Map<Meter, int> preview;
  final VoidCallback onLog;
  const MeterHud({super.key, required this.g, required this.preview, required this.onLog});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xCC120E0B),
        border: Border(bottom: BorderSide(color: P.line)),
      ),
      child: Column(children: [
        Row(children: [
          _chip('🗓 ${g.turn}/${Game.goalTurn}'),
          const SizedBox(width: 6),
          _chip('🪙 ${_fmt(g.mana)}',
              color: g.mana <= 0 ? P.red : P.goldSoft),
          if (g.streak >= 2) ...[
            const SizedBox(width: 6),
            _chip('🔥 ${g.streak}연승', color: P.blood, fill: true),
          ],
          const Spacer(),
          InkWell(
            onTap: onLog,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Text('📜', style: TextStyle(fontSize: 18)),
            ),
          ),
        ]),
        const SizedBox(height: 9),
        Row(
          children: Meter.values.map((m) {
            final hi = preview.containsKey(m);
            final delta = preview[m] ?? 0;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: MeterBar(
                  info: kMeters[m]!,
                  value: g.meters[m]!,
                  highlight: hi,
                  delta: delta,
                ),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _chip(String t, {Color color = P.parch, bool fill = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: fill ? P.blood.withOpacity(0.85) : P.panel,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: fill ? P.blood : P.line),
        ),
        child: Text(t,
            style: TextStyle(
                color: fill ? Colors.white : color,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      );

  static String _fmt(int v) {
    final neg = v < 0;
    var s = v.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${neg ? "-" : ""}$b';
  }
}

class MeterBar extends StatelessWidget {
  final MeterInfo info;
  final int value;
  final bool highlight;
  final int delta;
  const MeterBar(
      {super.key,
      required this.info,
      required this.value,
      required this.highlight,
      required this.delta});

  @override
  Widget build(BuildContext context) {
    final danger = value <= 20 || value >= 80;
    final barColor = danger ? P.red : info.color;
    return Column(children: [
      Text(info.icon,
          style: TextStyle(fontSize: 15, color: highlight ? Colors.white : null)),
      const SizedBox(height: 3),
      SizedBox(
        height: 8,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
                color: const Color(0xFF2A2018),
                borderRadius: BorderRadius.circular(5),
                border: highlight
                    ? Border.all(color: delta >= 0 ? P.green : P.red, width: 1.4)
                    : null),
          ),
          FractionallySizedBox(
            widthFactor: (value / 100).clamp(0.0, 1.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(5),
                boxShadow: danger
                    ? [BoxShadow(color: P.red.withOpacity(0.6), blurRadius: 6)]
                    : null,
              ),
            ),
          ),
        ]),
      ),
      if (highlight && delta != 0) ...[
        const SizedBox(height: 2),
        Text((delta > 0 ? '+' : '') + delta.toString(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: delta >= 0 ? P.green : P.red)),
      ],
    ]);
  }
}

// =============================================================================
//  스와이프 카드 스테이지
// =============================================================================
class SwipeStage extends StatefulWidget {
  final Game g;
  final ValueChanged<double> onDrag;
  final VoidCallback onSettle;
  const SwipeStage(
      {super.key, required this.g, required this.onDrag, required this.onSettle});
  @override
  State<SwipeStage> createState() => _SwipeStageState();
}

class _SwipeStageState extends State<SwipeStage> {
  double dx = 0;
  double width = 300;

  void _end() {
    final norm = (dx / (width * 0.5)).clamp(-1.0, 1.0);
    if (norm <= -0.55) {
      widget.onSettle();
      widget.g.choose(false);
    } else if (norm >= 0.55) {
      widget.onSettle();
      widget.g.choose(true);
    } else {
      setState(() => dx = 0);
      widget.onSettle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.g.card!;
    return LayoutBuilder(builder: (context, cons) {
      width = cons.maxWidth;
      final norm = (dx / (width * 0.5)).clamp(-1.0, 1.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: Column(children: [
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (d) {
                setState(() => dx += d.delta.dx);
                widget.onDrag(norm);
              },
              onHorizontalDragEnd: (_) => _end(),
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: Transform.rotate(
                  angle: norm * 0.12,
                  child: _cardFace(c, norm),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 버튼 대안 (데스크톱/접근성)
          Row(children: [
            Expanded(child: _choiceBtn(c.left, false)),
            const SizedBox(width: 10),
            Expanded(child: _choiceBtn(c.right, true)),
          ]),
          const SizedBox(height: 6),
          const Text('카드를 좌우로 밀거나, 아래 버튼을 누르십시오',
              style: TextStyle(color: P.muted, fontSize: 10.5)),
        ]),
      );
    });
  }

  Widget _cardFace(CardDef c, double norm) {
    final leftGlow = norm < -0.12;
    final rightGlow = norm > 0.12;
    return Container(
      decoration: BoxDecoration(
        color: P.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: leftGlow
              ? P.red
              : rightGlow
                  ? P.gold
                  : P.line,
          width: 2,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // 엠블럼 (코드 그래픽)
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: EmblemView(scene: c.scene)),
            // 좌우 선택 힌트
            if (leftGlow)
              _hint(Alignment.topLeft, c.left.label, P.red, -norm),
            if (rightGlow)
              _hint(Alignment.topRight, c.right.label, P.gold, norm),
          ]),
        ),
        // 텍스트 (한 줄)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: P.line)),
            color: Color(0xFF181210),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.speaker,
                style: const TextStyle(
                    color: P.gold, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(c.text,
                style: const TextStyle(color: P.parch, fontSize: 16, height: 1.45)),
          ]),
        ),
      ]),
    );
  }

  Widget _hint(Alignment a, String label, Color color, double strength) {
    return Align(
      alignment: a,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Opacity(
          opacity: strength.clamp(0.0, 1.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Widget _choiceBtn(Choice ch, bool right) {
    final color = right ? P.gold : P.blood;
    return Material(
      color: P.bg2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          widget.onSettle();
          widget.g.choose(right);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Row(children: [
            Text(right ? '→ ' : '← ',
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            Expanded(
              child: Text(ch.label,
                  textAlign: right ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
//  결과 뷰 (한 줄 결과 + 주사위 + 미터 변화 → 탭하여 계속)
// =============================================================================
class ResultView extends StatelessWidget {
  final Game g;
  const ResultView({super.key, required this.g});

  @override
  Widget build(BuildContext context) {
    final good = g.resultGood;
    final accent = good ? P.green : P.red;
    return GestureDetector(
      onTap: g.advance,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (g.lastRoll != null) ...[
            DiePip(roll: g.lastRoll!, crit: g.lastCrit, good: good),
            const SizedBox(height: 16),
          ],
          Text(g.lastCrit ? '⚡ 운명의 눈이 활짝 열렸다!' : (good ? '적중' : '빗나감'),
              style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(g.resultText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: P.parch, fontSize: 17, height: 1.6)),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (g.lastMana != 0)
                _delta('🪙', g.lastMana, gold: true),
              ...g.lastFx.entries
                  .map((e) => _delta(kMeters[e.key]!.icon, e.value)),
            ],
          ),
          const SizedBox(height: 30),
          Text('▶  탭하여 계속',
              style: TextStyle(
                  color: P.gold.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _delta(String icon, int v, {bool gold = false}) {
    final pos = v >= 0;
    final col = gold ? (pos ? P.goldSoft : P.red) : (pos ? P.green : P.red);
    final txt = gold
        ? '${pos ? "+" : "-"}${MeterHud._fmt(v.abs())}'
        : '${pos ? "+" : ""}$v';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: P.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: col.withOpacity(0.6)),
      ),
      child: Text('$icon $txt',
          style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }
}

// 주사위 눈 표시
class DiePip extends StatelessWidget {
  final int roll;
  final bool crit;
  final bool good;
  const DiePip({super.key, required this.roll, required this.crit, required this.good});
  @override
  Widget build(BuildContext context) {
    final c = crit
        ? P.gold
        : roll == 1
            ? P.blood
            : good
                ? P.green
                : P.red;
    return Container(
      width: 70,
      height: 70,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: P.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c, width: 2.5),
        boxShadow: [BoxShadow(color: c.withOpacity(0.5), blurRadius: 14)],
      ),
      child: Text('$roll',
          style: TextStyle(color: c, fontSize: 30, fontWeight: FontWeight.bold)),
    );
  }
}

// =============================================================================
//  종료 화면 (사망 / 승리)
// =============================================================================
class EndScreen extends StatelessWidget {
  final Game g;
  final bool victory;
  const EndScreen({super.key, required this.g, required this.victory});
  @override
  Widget build(BuildContext context) {
    final accent = victory ? P.gold : P.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 30),
          SizedBox(
            height: 130,
            width: 130,
            child: EmblemView(scene: victory ? Scene.throne : Scene.skull),
          ),
          const SizedBox(height: 18),
          Text(victory ? '대 륙 정 복' : '부 족 소 멸',
              style: TextStyle(
                  color: accent, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 3)),
          const SizedBox(height: 16),
          Text(g.endReason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: P.parch, fontSize: 15, height: 1.7)),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: P.bg2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: P.line),
            ),
            child: Column(children: [
              Text('🐅 이번 대는 ${g.turn}턴을 버텼습니다',
                  style: const TextStyle(color: P.parch, fontSize: 13)),
              const SizedBox(height: 6),
              Text('최고 기록 ${g.bestTurn}턴 · 누적 ${g.totalRuns}대째',
                  style: const TextStyle(color: P.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 26),
          _btn(victory ? '새로운 핏줄로 다시' : '재기의 부족 창설', accent, g.restart),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _btn(String t, Color c, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: Material(
          color: c,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(t,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      );
}

// =============================================================================
//  오프닝 시네마틱 (코드 애니메이션, 스킵 가능)
// =============================================================================
class Opening extends StatefulWidget {
  final VoidCallback onDone;
  const Opening({super.key, required this.onDone});
  @override
  State<Opening> createState() => _OpeningState();
}

class _OpeningState extends State<Opening> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200))
      ..forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _finish,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            // 단계별 텍스트
            String line = '';
            if (t > 0.30 && t < 0.62) {
              line = '잿더미 속에서, 식어가던 심장이 다시 뛴다.';
            } else if (t >= 0.62 && t < 0.86) {
              line = '빼앗긴 모든 것을 — 그 위에 의장의 머리까지.';
            }
            return Container(
              color: Colors.black,
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: OpeningPainter(t))),
                if (line.isNotEmpty)
                  Align(
                    alignment: const Alignment(0, 0.55),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(line,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: P.parch.withOpacity(((t - 0.30) * 4).clamp(0.0, 1.0)),
                              fontSize: 15,
                              height: 1.6)),
                    ),
                  ),
                if (t > 0.86)
                  Align(
                    alignment: const Alignment(0, -0.1),
                    child: Opacity(
                      opacity: ((t - 0.86) * 7).clamp(0.0, 1.0),
                      child: const Text('어 흥',
                          style: TextStyle(
                              color: P.gold,
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 12)),
                    ),
                  ),
                Positioned(
                  top: 14,
                  right: 16,
                  child: TextButton(
                    onPressed: _finish,
                    child: Text('건너뛰기 ▶',
                        style: TextStyle(color: P.muted.withOpacity(0.8), fontSize: 13)),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
//  살아있는 배경 — 떠오르는 잿불 파티클 + 그라데이션
// =============================================================================
class LivingBackground extends StatefulWidget {
  const LivingBackground({super.key});
  @override
  State<LivingBackground> createState() => _LivingBackgroundState();
}

class _LivingBackgroundState extends State<LivingBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Ember> _embers;

  @override
  void initState() {
    super.initState();
    final r = Random(7);
    _embers = List.generate(
        34,
        (i) => _Ember(
              x: r.nextDouble(),
              phase: r.nextDouble(),
              speed: 0.25 + r.nextDouble() * 0.5,
              size: 1.0 + r.nextDouble() * 2.6,
              drift: (r.nextDouble() - 0.5) * 0.06,
            ));
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(painter: BackgroundPainter(_c.value, _embers)),
    );
  }
}

class _Ember {
  final double x, phase, speed, size, drift;
  const _Ember(
      {required this.x,
      required this.phase,
      required this.speed,
      required this.size,
      required this.drift});
}

class BackgroundPainter extends CustomPainter {
  final double t;
  final List<_Ember> embers;
  BackgroundPainter(this.t, this.embers);

  @override
  void paint(Canvas canvas, Size size) {
    // 어두운 세로 그라데이션
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1C140D), Color(0xFF0B0907)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // 바닥의 은은한 불빛
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [P.gold.withOpacity(0.10), P.gold.withOpacity(0.0)],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 1.02),
          radius: size.width * 0.9));
    canvas.drawRect(Offset.zero & size, glow);

    // 떠오르는 잿불
    final p = Paint();
    for (final e in embers) {
      final prog = (e.phase + t * e.speed) % 1.0;
      final y = size.height * (1.05 - prog * 1.1);
      final x = size.width * e.x + sin((prog + e.phase) * 6.28) * size.width * e.drift * 6;
      final a = (sin(prog * 3.14)).clamp(0.0, 1.0) * 0.6;
      p.color = Color.lerp(P.blood, P.gold, prog)!.withOpacity(a);
      canvas.drawCircle(Offset(x, y), e.size, p);
    }
  }

  @override
  bool shouldRepaint(covariant BackgroundPainter old) => true;
}

// =============================================================================
//  오프닝 페인터 — 잿불 → 호랑이 눈 뜨임 → (텍스트/타이틀은 위젯이 담당)
// =============================================================================
class OpeningPainter extends CustomPainter {
  final double t;
  OpeningPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;

    // 초반: 바닥 잿불 번짐
    final emberA = (1 - (t * 1.6)).clamp(0.0, 1.0);
    if (emberA > 0) {
      final g = Paint()
        ..shader = RadialGradient(
          colors: [P.blood.withOpacity(0.5 * emberA), Colors.transparent],
        ).createShader(Rect.fromCircle(
            center: Offset(cx, size.height * 0.8), radius: size.width * 0.8));
      canvas.drawRect(Offset.zero & size, g);
    }

    // 떠오르는 불씨들
    final rng = _det();
    final sp = Paint();
    for (int i = 0; i < 40; i++) {
      final ph = rng();
      final prog = (ph + t * (0.5 + rng() * 0.6)) % 1.0;
      final y = size.height * (1.0 - prog);
      final x = size.width * rng();
      sp.color = Color.lerp(P.blood, P.gold, prog)!.withOpacity((sin(prog * 3.14)) * 0.55);
      canvas.drawCircle(Offset(x, y), 1.2 + rng() * 2.0, sp);
    }

    // 눈 뜨임 (t 0.35~0.85): 두 눈
    final eyeOpen = ((t - 0.35) / 0.4).clamp(0.0, 1.0);
    if (eyeOpen > 0) {
      _eye(canvas, Offset(cx - size.width * 0.13, cy), size.width * 0.10, eyeOpen);
      _eye(canvas, Offset(cx + size.width * 0.13, cy), size.width * 0.10, eyeOpen);
    }
  }

  void _eye(Canvas canvas, Offset c, double r, double open) {
    // 안광
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [P.gold.withOpacity(0.9 * open), Colors.transparent],
      ).createShader(Rect.fromCircle(center: c, radius: r * 2.2));
    canvas.drawCircle(c, r * 2.2, glow);

    // 눈꺼풀로 잘린 눈 모양 (아몬드)
    final h = r * open;
    final path = Path()
      ..moveTo(c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy - h, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy + h, c.dx - r, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFE9A8).withOpacity(open));

    // 세로 동공
    if (open > 0.4) {
      final pupil = Paint()..color = Colors.black.withOpacity((open - 0.4) / 0.6);
      canvas.drawOval(
          Rect.fromCenter(center: c, width: r * 0.34, height: h * 1.5), pupil);
    }
  }

  // 결정적 의사난수 (페인트마다 동일 패턴)
  double Function() _det() {
    int s = 1234567;
    return () {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      return s / 0x7fffffff;
    };
  }

  @override
  bool shouldRepaint(covariant OpeningPainter old) => old.t != t;
}

// =============================================================================
//  씬 엠블럼 — 종류별로 코드로 그린 기하학 글리프
// =============================================================================
class EmblemView extends StatelessWidget {
  final Scene scene;
  const EmblemView({super.key, required this.scene});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF241B14), Color(0xFF130E0A)],
          radius: 0.9,
        ),
      ),
      child: CustomPaint(painter: EmblemPainter(scene), child: const SizedBox.expand()),
    );
  }
}

class EmblemPainter extends CustomPainter {
  final Scene scene;
  EmblemPainter(this.scene);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(size.width, size.height) * 0.3;
    final accent = _accent(scene);
    final fill = Paint()..color = accent.withOpacity(0.92);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = accent;

    switch (scene) {
      case Scene.tiger:
        _tiger(canvas, cx, cy, r, fill, line, accent);
        break;
      case Scene.wolf:
        _wolf(canvas, cx, cy, r, fill, line);
        break;
      case Scene.eye:
        _eye(canvas, cx, cy, r, fill, line, accent);
        break;
      case Scene.coin:
        _coin(canvas, cx, cy, r, accent);
        break;
      case Scene.throne:
        _throne(canvas, cx, cy, r, fill, accent);
        break;
      case Scene.skull:
        _skull(canvas, cx, cy, r, fill);
        break;
      case Scene.snake:
        _snake(canvas, cx, cy, r, line);
        break;
      case Scene.fire:
        _fire(canvas, cx, cy, r, accent);
        break;
      case Scene.hunter:
        _hunter(canvas, cx, cy, r, fill);
        break;
      case Scene.totem:
        _totem(canvas, cx, cy, r, fill, line, accent);
        break;
    }
  }

  Color _accent(Scene s) {
    switch (s) {
      case Scene.tiger:
        return P.gold;
      case Scene.wolf:
        return const Color(0xFFB7C2CC);
      case Scene.eye:
        return const Color(0xFFBA8FE0);
      case Scene.coin:
        return P.goldSoft;
      case Scene.throne:
        return P.blood;
      case Scene.skull:
        return const Color(0xFFCBBBA6);
      case Scene.snake:
        return P.green;
      case Scene.fire:
        return const Color(0xFFE8702E);
      case Scene.hunter:
        return const Color(0xFF8E7CC3);
      case Scene.totem:
        return const Color(0xFFD7B86A);
    }
  }

  void _glow(Canvas canvas, double cx, double cy, double r, Color c) {
    final g = Paint()
      ..shader = RadialGradient(colors: [c.withOpacity(0.28), Colors.transparent])
          .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 2.4));
    canvas.drawCircle(Offset(cx, cy), r * 2.4, g);
  }

  void _tiger(Canvas canvas, double cx, double cy, double r, Paint fill, Paint line, Color a) {
    _glow(canvas, cx, cy, r, a);
    // 귀
    final ear = Path()
      ..moveTo(cx - r * 0.9, cy - r * 0.6)
      ..lineTo(cx - r * 0.5, cy - r * 1.15)
      ..lineTo(cx - r * 0.2, cy - r * 0.7)
      ..close()
      ..moveTo(cx + r * 0.9, cy - r * 0.6)
      ..lineTo(cx + r * 0.5, cy - r * 1.15)
      ..lineTo(cx + r * 0.2, cy - r * 0.7)
      ..close();
    canvas.drawPath(ear, fill);
    // 얼굴
    canvas.drawCircle(Offset(cx, cy), r, fill);
    // 눈
    final eye = Paint()..color = const Color(0xFF1A1410);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - r * 0.4, cy - r * 0.1), width: r * 0.34, height: r * 0.5), eye);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + r * 0.4, cy - r * 0.1), width: r * 0.34, height: r * 0.5), eye);
    // 코/주둥이
    canvas.drawCircle(Offset(cx, cy + r * 0.45), r * 0.12, eye);
    // 줄무늬
    final st = Paint()
      ..color = const Color(0xFF1A1410)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - r * 0.2, cy - r * 0.9), Offset(cx - r * 0.1, cy - r * 0.5), st);
    canvas.drawLine(Offset(cx + r * 0.2, cy - r * 0.9), Offset(cx + r * 0.1, cy - r * 0.5), st);
    canvas.drawLine(Offset(cx - r * 0.95, cy), Offset(cx - r * 0.5, cy + r * 0.05), st);
    canvas.drawLine(Offset(cx + r * 0.95, cy), Offset(cx + r * 0.5, cy + r * 0.05), st);
  }

  void _wolf(Canvas canvas, double cx, double cy, double r, Paint fill, Paint line) {
    _glow(canvas, cx, cy, r, line.color);
    final head = Path()
      ..moveTo(cx, cy + r * 1.1) // 주둥이 아래
      ..lineTo(cx - r * 0.7, cy + r * 0.3)
      ..lineTo(cx - r * 0.95, cy - r * 1.05) // 왼 귀
      ..lineTo(cx - r * 0.4, cy - r * 0.5)
      ..lineTo(cx + r * 0.4, cy - r * 0.5)
      ..lineTo(cx + r * 0.95, cy - r * 1.05) // 오른 귀
      ..lineTo(cx + r * 0.7, cy + r * 0.3)
      ..close();
    canvas.drawPath(head, fill);
    final eye = Paint()..color = P.red;
    canvas.drawCircle(Offset(cx - r * 0.32, cy - r * 0.1), r * 0.12, eye);
    canvas.drawCircle(Offset(cx + r * 0.32, cy - r * 0.1), r * 0.12, eye);
  }

  void _eye(Canvas canvas, double cx, double cy, double r, Paint fill, Paint line, Color a) {
    _glow(canvas, cx, cy, r, a);
    // 방사선
    final ray = Paint()
      ..color = a.withOpacity(0.5)
      ..strokeWidth = 2;
    for (int i = 0; i < 12; i++) {
      final ang = i * 3.14159 / 6;
      canvas.drawLine(
          Offset(cx + cos(ang) * r * 1.3, cy + sin(ang) * r * 1.3),
          Offset(cx + cos(ang) * r * 1.7, cy + sin(ang) * r * 1.7),
          ray);
    }
    final almond = Path()
      ..moveTo(cx - r * 1.2, cy)
      ..quadraticBezierTo(cx, cy - r * 0.8, cx + r * 1.2, cy)
      ..quadraticBezierTo(cx, cy + r * 0.8, cx - r * 1.2, cy)
      ..close();
    canvas.drawPath(almond, Paint()..color = a.withOpacity(0.18));
    canvas.drawPath(almond, line);
    canvas.drawCircle(Offset(cx, cy), r * 0.45, fill);
    canvas.drawCircle(Offset(cx, cy), r * 0.18, Paint()..color = Colors.black);
  }

  void _coin(Canvas canvas, double cx, double cy, double r, Color a) {
    for (int i = 0; i < 4; i++) {
      final yy = cy + r * 0.7 - i * r * 0.42;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, yy), width: r * 2.0, height: r * 0.7),
          Paint()..color = a.withOpacity(0.92));
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, yy), width: r * 2.0, height: r * 0.7),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.black.withOpacity(0.3));
    }
  }

  void _throne(Canvas canvas, double cx, double cy, double r, Paint fill, Color a) {
    _glow(canvas, cx, cy, r, a);
    final seat = Paint()..color = const Color(0xFF2A1410);
    // 등받이
    canvas.drawRect(
        Rect.fromLTRB(cx - r * 0.8, cy - r * 1.3, cx + r * 0.8, cy + r * 0.9), seat);
    // 가시 왕관
    final spikes = Path();
    for (int i = 0; i < 5; i++) {
      final x0 = cx - r * 0.8 + i * r * 0.4;
      spikes
        ..moveTo(x0, cy - r * 1.3)
        ..lineTo(x0 + r * 0.2, cy - r * 1.7)
        ..lineTo(x0 + r * 0.4, cy - r * 1.3);
    }
    canvas.drawPath(spikes, fill);
    // 불타는 균열
    final crack = Paint()
      ..color = a
      ..strokeWidth = 3;
    canvas.drawLine(Offset(cx, cy - r * 1.1), Offset(cx - r * 0.2, cy + r * 0.7), crack);
  }

  void _skull(Canvas canvas, double cx, double cy, double r, Paint fill) {
    canvas.drawCircle(Offset(cx, cy - r * 0.2), r, fill);
    canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy + r * 0.7), width: r * 1.1, height: r * 0.8),
        fill);
    final hole = Paint()..color = Colors.black;
    canvas.drawCircle(Offset(cx - r * 0.4, cy - r * 0.2), r * 0.28, hole);
    canvas.drawCircle(Offset(cx + r * 0.4, cy - r * 0.2), r * 0.28, hole);
    canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy + r * 0.3), width: r * 0.18, height: r * 0.4),
        hole);
  }

  void _snake(Canvas canvas, double cx, double cy, double r, Paint line) {
    final p = Path()..moveTo(cx - r * 1.2, cy + r);
    for (int i = 0; i <= 8; i++) {
      final x = cx - r * 1.2 + (r * 2.4) * i / 8;
      final y = cy + r - (i / 8) * r * 2 + sin(i * 1.2) * r * 0.35;
      p.lineTo(x, y);
    }
    final wide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = line.color;
    canvas.drawPath(p, wide);
    canvas.drawCircle(Offset(cx + r * 1.2, cy - r), r * 0.22, Paint()..color = line.color);
    canvas.drawCircle(Offset(cx + r * 1.25, cy - r * 1.05), r * 0.06, Paint()..color = Colors.black);
  }

  void _fire(Canvas canvas, double cx, double cy, double r, Color a) {
    _glow(canvas, cx, cy, r, a);
    Path flame(double scale, Color col) {
      final p = Path()
        ..moveTo(cx, cy + r)
        ..quadraticBezierTo(cx - r * scale, cy, cx - r * 0.3 * scale, cy - r * 0.5 * scale)
        ..quadraticBezierTo(cx - r * 0.1 * scale, cy - r * 1.2 * scale, cx, cy - r * 1.6 * scale)
        ..quadraticBezierTo(cx + r * 0.1 * scale, cy - r * 1.2 * scale, cx + r * 0.3 * scale, cy - r * 0.5 * scale)
        ..quadraticBezierTo(cx + r * scale, cy, cx, cy + r)
        ..close();
      return p;
    }
    canvas.drawPath(flame(1.0, a), Paint()..color = a.withOpacity(0.9));
    canvas.drawPath(flame(0.55, P.gold), Paint()..color = P.goldSoft.withOpacity(0.95));
  }

  void _hunter(Canvas canvas, double cx, double cy, double r, Paint fill) {
    final cloak = Path()
      ..moveTo(cx, cy - r * 1.2)
      ..quadraticBezierTo(cx - r * 0.9, cy - r * 0.8, cx - r * 0.8, cy + r * 1.2)
      ..lineTo(cx + r * 0.8, cy + r * 1.2)
      ..quadraticBezierTo(cx + r * 0.9, cy - r * 0.8, cx, cy - r * 1.2)
      ..close();
    canvas.drawPath(cloak, fill);
    // 후드 그림자 속 눈
    final eye = Paint()..color = P.red;
    canvas.drawCircle(Offset(cx - r * 0.22, cy - r * 0.4), r * 0.1, eye);
    canvas.drawCircle(Offset(cx + r * 0.22, cy - r * 0.4), r * 0.1, eye);
  }

  void _totem(Canvas canvas, double cx, double cy, double r, Paint fill, Paint line, Color a) {
    _glow(canvas, cx, cy, r, a);
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 1.1, height: r * 2.4),
        const Radius.circular(8));
    canvas.drawRRect(body, fill);
    final mk = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawCircle(Offset(cx - r * 0.22, cy - r * 0.5), r * 0.12, mk);
    canvas.drawCircle(Offset(cx + r * 0.22, cy - r * 0.5), r * 0.12, mk);
    canvas.drawLine(Offset(cx - r * 0.3, cy + r * 0.2), Offset(cx + r * 0.3, cy + r * 0.2),
        Paint()
          ..color = Colors.black.withOpacity(0.55)
          ..strokeWidth = 3);
    // 날개 장식
    canvas.drawLine(Offset(cx - r * 0.55, cy - r), Offset(cx - r * 1.1, cy - r * 1.3), line);
    canvas.drawLine(Offset(cx + r * 0.55, cy - r), Offset(cx + r * 1.1, cy - r * 1.3), line);
  }

  @override
  bool shouldRepaint(covariant EmblemPainter old) => old.scene != scene;
}
