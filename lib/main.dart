// =============================================================================
//  PROJECT AUHHEUNG — 타이니 수다·1회차 풀가이드 빌드 v8 (Flutter Web / DartPad)
//  성격   : v7 단일화면 위에 타이니 NPC의 끊임없는 수다 + 1회차 무지성 가이드.
//  ▣ v8 신규
//    - 1회차(2회차 전) 내내 타이니 풀가이드 + ⭐추천 (무지성 따라가기)
//    - 사건마다 타이니가 말 검(랜덤 대사 풀) — 지속적 뽕
//    - 실패 시 격려 / 실패 직후 성공 시 '오뚝이 컴백' 특별 환호 + 골드 연출
//    - 연속 성공 시 뽕 가중 대사
//  (이하 v7 단일화면 구조 계승)
//  동기화 : GDD v28.0 / Master DB v28.0
//  Modifier: FLOOR((스탯-10)/2) — GDD #002 (대장님 확정)
//
//  ▣ v7 구조 대수술
//    - 단일 게임 화면: [상단 HUD] · [중앙 사건/결과 슬라이드] · [하단 선택지/다음]
//    - 메인 퀘스트는 '들어갔다 나오기' 없이 사건→선택→결과→다음 사건이 끊김없이 흐름
//    - 한 지역 끝나면 자동으로 다음 목적지로 (지역 메뉴 라우팅 제거)
//    - 사냥/상점/캐릭터/월드맵은 화면 이동이 아니라 '아래에서 올라오는 모달'
//  ▣ 계승: D20(#003)·유지비(#007)·파산/마진콜(#004/#008)·레벨업(#011)·
//    업적/칭호(#014/#015)·돌발뉴스(#010)·보스(#025)·S형(#024)·신용(#005)·
//    도파민 고속도로(#089~#092)·연출(#041~#050: 타이니/카운트업/크리티컬)
//  ※ 그래픽은 지역 배경 + 캐릭터 초상화 자리만 추후 삽입.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const AuhHeungApp());

class AuhHeungApp extends StatelessWidget {
  const AuhHeungApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project AuhHeung v8',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0B09),
        // ※ monospace 강제 제거: 모바일에서 이모지(🐯😼🩸 등)가 ?/□로 깨지는 원인.
        //   기본 폰트 + 이모지 폰트 fallback을 명시해 컬러 이모지가 정상 렌더되게 함.
        fontFamilyFallback: const [
          'Noto Color Emoji', // 웹폰트로 직접 로드 — 모든 기기 공통(최우선)
          'Apple Color Emoji', // iOS / macOS
          'Segoe UI Emoji', // Windows
        ],
        colorScheme: const ColorScheme.dark(primary: Color(0xFFE8A33D)),
      ),
      home: const GameScreen(),
    );
  }
}

// =============================================================================
//  [상수 금고]
// =============================================================================
class Cfg {
  const Cfg._();
  static const int diceMin = 1, diceMax = 20;
  static const int critSuccess = 20, critFail = 1;
  static const double critSuccessMul = 1.5, critFailMul = 1.2;
  static const Map<int, int> lvBonus = {1: 0, 2: 1, 3: 2, 4: 3, 5: 5};
  static const Map<int, int> lvReqExp = {1: 0, 2: 1000, 3: 2500, 4: 5000, 5: 9000};
  static const int maxLevel = 5;
  static const int goldMin = -9999999, goldMax = 9999999999;
  static const int bankruptcy = -20000, forcedGrade = 4, graceTurns = 3;
  static const int upBase = 1000, upPer = 150, upNormalLast = 12;
  static const int upEndless = 3000, upCycle = 5, upSurcharge = 500;
  static const int hyperLast = 15, hyperEnd = 16, hyperEndLv = 4;
  static const int hyperMinRoll = 10;
  static const double hyperExpMul = 3.0;
  static const int hyperForceCritMargin = 3;
  static const double newsChance = 0.025;
  static const int marginCallStreak = 2;
  static const int delinquencyCreditPenalty = 150;
  static const int sUnlockStatTotal = 30;
  static const int sUnlockGold = 70000;
  static const int sDc = 25;
  static const int restCreditRecover = 20;
  // [게임성] 연승 보너스: 연속 성공마다 보상 +5%, 최대 6연승(+30%)
  static const double streakBonusPer = 0.05;
  static const int streakBonusCap = 6;
  // [게임성] 가변 보상(변동비율 강화) — 성공 보상 1.0~1.35배 랜덤
  static const double rewardVarMin = 1.0;
  static const double rewardVarMax = 1.35;
  // [게임성] 잭팟: 성공 시 8% 확률로 보상 2.5배 폭증
  static const double jackpotChance = 0.08;
  static const double jackpotMul = 2.5;
  // [게임성] 다회차 유산(메타 성장) — 클리어/패배 시 다음 회차 영구 보너스
  static const int legacyStatClear = 2, legacyGoldClear = 20000;
  static const int legacyStatLose = 1, legacyGoldLose = 5000;
}

// =============================================================================
//  [열거형]
// =============================================================================
enum TribeStat { wildness, influence, leather }

extension TribeStatX on TribeStat {
  String get label => this == TribeStat.wildness
      ? '야성'
      : this == TribeStat.influence
          ? '영향력'
          : '가죽';
  String get icon => this == TribeStat.wildness
      ? '🔥'
      : this == TribeStat.influence
          ? '👑'
          : '🛡';
}

enum ChoiceType { aggressive, conservative, shortSale, transcend }

extension ChoiceTypeX on ChoiceType {
  String get tag => this == ChoiceType.aggressive
      ? 'A'
      : this == ChoiceType.conservative
          ? 'B'
          : this == ChoiceType.shortSale
              ? 'C'
              : 'S';
  String get concept => this == ChoiceType.aggressive
      ? '야성 약탈'
      : this == ChoiceType.conservative
          ? '안정 협상'
          : this == ChoiceType.shortSale
              ? '역베팅'
              : '초월';
  TribeStat get stat => this == ChoiceType.aggressive
      ? TribeStat.wildness
      : this == ChoiceType.conservative
          ? TribeStat.influence
          : TribeStat.leather;
  int get baseDc => this == ChoiceType.aggressive
      ? 15
      : this == ChoiceType.conservative
          ? 11
          : this == ChoiceType.shortSale
              ? 19
              : Cfg.sDc;
}

enum DiceOutcome { criticalSuccess, success, failure, criticalFailure }

extension DiceOutcomeX on DiceOutcome {
  String get label => this == DiceOutcome.criticalSuccess
      ? '대성공'
      : this == DiceOutcome.success
          ? '성공'
          : this == DiceOutcome.failure
              ? '실패'
              : '대실패';
  bool get isSuccess =>
      this == DiceOutcome.criticalSuccess || this == DiceOutcome.success;
  Color get color => this == DiceOutcome.criticalSuccess
      ? const Color(0xFFFFD54F)
      : this == DiceOutcome.success
          ? const Color(0xFF81C784)
          : this == DiceOutcome.failure
              ? const Color(0xFFE57373)
              : const Color(0xFFB7402E);
}

enum Grade { common, rare, ancient, mythic }

extension GradeX on Grade {
  String get label => this == Grade.common
      ? '일반'
      : this == Grade.rare
          ? '희귀'
          : this == Grade.ancient
              ? '고대'
              : '신화';
  int get rank => index;
  Color get color => this == Grade.common
      ? const Color(0xFF9C8C7E)
      : this == Grade.rare
          ? const Color(0xFF64B5F6)
          : this == Grade.ancient
              ? const Color(0xFFBA68C8)
              : const Color(0xFFFFD54F);
}

enum EquipSlot { weapon, armor, accessory, mythic }

extension EquipSlotX on EquipSlot {
  String get label => this == EquipSlot.weapon
      ? '무기'
      : this == EquipSlot.armor
          ? '방어구'
          : this == EquipSlot.accessory
              ? '장신구'
              : '신화';
  String get icon => this == EquipSlot.weapon
      ? '⚔'
      : this == EquipSlot.armor
          ? '🥋'
          : this == EquipSlot.accessory
              ? '💍'
              : '🎽';
}

// 메인 화면 중앙 단계
enum Stage { intro, story, resolution, boss, news, ending, gameOver }

// 아래에서 올라오는 모달
enum Overlay { none, worldMap, shop, hunt, character }

// =============================================================================
//  [Model] 장비
// =============================================================================
class Equipment {
  final String id, name, note;
  final Grade grade;
  final EquipSlot slot;
  final Map<TribeStat, int> statBonus;
  final bool isMythicSuit;
  const Equipment(this.id, this.name, this.grade, this.slot,
      {this.statBonus = const {}, this.isMythicSuit = false, this.note = ''});

  // ── 세이브 직렬화 ──
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'grade': grade.index,
        'slot': slot.index,
        'sb': statBonus.map((k, v) => MapEntry(k.index.toString(), v)),
        'm': isMythicSuit,
      };
  static Equipment fromJson(Map<String, dynamic> j) {
    if (j['m'] == true) return kMythicSuit;
    final sb = <TribeStat, int>{};
    (j['sb'] as Map).forEach((k, v) {
      sb[TribeStat.values[int.parse(k as String)]] = v as int;
    });
    return Equipment(
      j['id'] as String,
      j['name'] as String,
      Grade.values[j['grade'] as int],
      EquipSlot.values[j['slot'] as int],
      statBonus: sb,
      isMythicSuit: false,
      note: (j['note'] as String?) ?? '',
    );
  }
}

const Equipment kMythicSuit = Equipment(
  'ITM_MYTHIC_001', '타이거 엠페러 하이퍼 슈트', Grade.mythic, EquipSlot.mythic,
  statBonus: {TribeStat.wildness: 5, TribeStat.influence: 3, TribeStat.leather: 4},
  isMythicSuit: true,
  note: '굴림 5이하→6 보정 · C형 대성공 보상 +20%',
);

// =============================================================================
//  [Model] 유물(Relic) — 영구 패시브. 사냥·지역클리어·보스로 수집(StS식 빌드)
// =============================================================================
enum RelicFx {
  cGold, // C형 성공 보상 +%
  huntGold, // 사냥 보상 +%
  upkeep, // 유지비 -%
  dice, // 모든 판정 +N
  minRoll, // 주사위 최소 눈금 +N(상시)
  income, // 매 턴 시작 +금고
  jackpot, // 잭팟 확률 +
  comeback, // 컴백(실수후성공) 보상 +%
  news, // 돌발뉴스 면역
  streak, // 연승 보너스 +%p
}

class Relic {
  final String id, name, emoji, desc;
  final RelicFx fx;
  final num v;
  const Relic(this.id, this.name, this.emoji, this.fx, this.v, this.desc);
}

const Map<String, Relic> kRelics = {
  'claw': Relic('claw', '황금 발톱', '🦅', RelicFx.cGold, 0.15, 'C형(역베팅) 성공 보상 +15%'),
  'idol': Relic('idol', '황금 우상', '🗿', RelicFx.huntGold, 0.25, '사냥 보상 +25%'),
  'hide': Relic('hide', '불멸의 가죽', '🛡', RelicFx.upkeep, 0.15, '매 턴 유지비 -15%'),
  'instinct': Relic('instinct', '포식자의 직감', '👁', RelicFx.dice, 1, '모든 판정 +1'),
  'heart': Relic('heart', '맹수의 심장', '❤️‍🔥', RelicFx.minRoll, 1, '주사위 최소 눈금 +1 (상시)'),
  'pact': Relic('pact', '그림자 계약', '📜', RelicFx.income, 2000, '매 턴 시작 시 금고 +2,000'),
  'coin': Relic('coin', '도박꾼의 동전', '🪙', RelicFx.jackpot, 0.10, '잭팟 확률 +10%p'),
  'fang': Relic('fang', '복수의 송곳니', '🦷', RelicFx.comeback, 0.4, '오뚝이 컴백 보상 +40%'),
  'letter': Relic('letter', '의회의 밀서', '✉️', RelicFx.news, 1, '대륙 돌발 뉴스(악재) 면역'),
  'totem': Relic('totem', '야성의 토템', '🪬', RelicFx.streak, 0.05, '연승 보너스 +5%p 가중'),
};

// =============================================================================
//  [Model] 상점 — GDD #016 암시장
// =============================================================================
class ShopItem {
  final String code, name, effectDesc;
  final int price, requiredGradeOrBetter;
  final Equipment? equipment;
  final bool isCreditPotion;
  const ShopItem(this.code, this.name, this.price, this.requiredGradeOrBetter,
      this.effectDesc,
      {this.equipment, this.isCreditPotion = false});
}

const List<ShopItem> kBlackMarket = [
  ShopItem('SHP_001', '투기꾼의 주사위', 5000, 3, '가죽 +1 · 야성 판정 보너스 최소 +1',
      equipment: Equipment('SHP_001', '투기꾼의 주사위', Grade.rare, EquipSlot.accessory,
          statBonus: {TribeStat.leather: 1}, note: '야성 판정 보너스 최소 +1')),
  ShopItem('SHP_002', '의회 스파이의 인장', 12000, 2, '영향력 +2 · 돌발뉴스 확률 5% 감소',
      equipment: Equipment('SHP_002', '의회 스파이의 인장', Grade.rare, EquipSlot.accessory,
          statBonus: {TribeStat.influence: 2}, note: '돌발뉴스 확률 -5%p')),
  ShopItem('SHP_003', '헤지펀드 호랑이의 발톱', 35000, 1, '야성 +4 · 영향력 +2 · 공매도 보상 10%',
      equipment: Equipment('SHP_003', '헤지펀드 호랑이의 발톱', Grade.ancient, EquipSlot.weapon,
          statBonus: {TribeStat.wildness: 4, TribeStat.influence: 2},
          note: 'C형(공매도) 보상 +10%')),
  ShopItem('SHP_004', '파산자의 기적 (포션)', 3000, 4, '즉시 신용 등급 1단계 상승(최대 2등급)',
      isCreditPotion: true),
];

// =============================================================================
//  [Model] 사냥감
// =============================================================================
class HuntTarget {
  final String name;
  final TribeStat stat;
  final int dc, goldWin, expWin, goldLose;
  final Map<TribeStat, int> statLose;
  const HuntTarget(this.name, this.stat, this.dc, this.goldWin, this.expWin,
      this.goldLose,
      {this.statLose = const {}});
}

// =============================================================================
//  [Model] 지역
// =============================================================================
class Region {
  final String id, name, emoji, desc;
  final List<Color> bg;
  final int chapter;
  final List<String> questEventIds;
  final List<HuntTarget> hunts;
  final bool hasShop, isCamp, hasBoss;
  const Region(this.id, this.name, this.emoji, this.bg, this.chapter, this.desc,
      {this.questEventIds = const [],
      this.hunts = const [],
      this.hasShop = false,
      this.isCamp = false,
      this.hasBoss = false});
}

const Map<String, Region> kRegions = {
  'camp': Region('camp', '부족 야영지', '🏕',
      [Color(0xFF2A2418), Color(0xFF14110A)], 0,
      '대장님의 본거지. 모닥불 곁에서 정비하고 전열을 가다듬는 곳입니다.',
      isCamp: true),
  'valley': Region('valley', '남쪽 황금 계곡', '🌄',
      [Color(0xFF3E2F12), Color(0xFF1A1407)], 1,
      '황금빛 꿀송이가 발견된 풍요와 광기의 계곡. 첫 패권 다툼이 시작됩니다.',
      questEventIds: ['SCR_001', 'SCR_002', 'SCR_003'],
      hunts: [
        HuntTarget('이빨 없는 토끼 부족', TribeStat.wildness, 12, 12000, 100, -2000),
        HuntTarget('떠돌이 들개 약탈단', TribeStat.wildness, 14, 18000, 160, -4000,
            statLose: {TribeStat.wildness: -1}),
      ]),
  'plain': Region('plain', '무너지는 도미노 평원', '🏚️',
      [Color(0xFF2C2622), Color(0xFF14110F)], 2,
      '연쇄 파산이 휩쓰는 잿빛 평원. 무너진 부족의 영토가 널려 있습니다.',
      questEventIds: ['SCR_004', 'SCR_005', 'SCR_006'],
      hunts: [
        HuntTarget('하이에나 무리', TribeStat.leather, 16, 26000, 240, -7000,
            statLose: {TribeStat.leather: -2}),
        HuntTarget('부도 부족 잔당', TribeStat.influence, 17, 30000, 280, -8000),
      ]),
  'market': Region('market', '암시장 뒷골목', '🏪',
      [Color(0xFF1E1A22), Color(0xFF0D0B10)], 0,
      '그림자 의회의 눈을 피해 온갖 장물과 비밀 병기가 거래되는 뒷골목입니다.',
      hasShop: true),
  'tower': Region('tower', '마법공학 첨탑 도시', '🗼',
      [Color(0xFF1B2238), Color(0xFF0C0F1A)], 3,
      '신기술 버블이 하늘을 찌르는 첨탑의 도시. 광기와 혁신이 뒤섞입니다.',
      questEventIds: ['SCR_007', 'SCR_008', 'SCR_009'],
      hunts: [
        HuntTarget('폭주한 유령 부족', TribeStat.wildness, 19, 40000, 360, -10000,
            statLose: {TribeStat.wildness: -2}),
      ]),
  'throne': Region('throne', '그림자 의회 흑요석 왕좌', '🔥',
      [Color(0xFF3A0F0C), Color(0xFF160605)], 4,
      '대륙을 조종하는 흑막의 심장부. 최후의 결전이 기다립니다.',
      questEventIds: ['SCR_010', 'SCR_011', 'SCR_012'],
      hasBoss: true),
  'arena': Region('arena', '피의 투기장', '⚔️',
      [Color(0xFF2A1010), Color(0xFF120606)], 0,
      '맹수들이 전리품을 걸고 끝없이 충돌하는 투기장. 반복 도전으로 자산을 불립니다.',
      hunts: [
        HuntTarget('굶주린 검투 맹수', TribeStat.wildness, 15, 22000, 200, -5000),
        HuntTarget('투기장 챔피언', TribeStat.leather, 20, 50000, 450, -15000,
            statLose: {TribeStat.leather: -2}),
      ]),
};

const Map<String, String> kUnlockChain = {
  'valley': 'plain',
  'plain': 'tower',
  'tower': 'throne',
};
// 메인 스토리 자동 진행 순서(지역)
const List<String> kStoryOrder = ['valley', 'plain', 'tower', 'throne'];
const List<String> kInitialRegions = ['camp', 'valley', 'market'];

// =============================================================================
//  [Model] 업적/칭호
// =============================================================================
class TitleDef {
  final String code, title, achName, effect;
  const TitleDef(this.code, this.title, this.achName, this.effect);
}

const Map<String, TitleDef> kTitles = {
  'ACH_001': TitleDef('ACH_001', '공매도의 군주', '광기의 불나방', 'C형 성공 보상 +5% · (장착) C형 DC -2'),
  'ACH_002': TitleDef('ACH_002', '불패의 가죽', '대륙의 철벽 맷집', '매 턴 고정 유지비 -10%'),
  'ACH_003': TitleDef('ACH_003', '월스트리트의 호랑이', '보이지 않는 손의 총아', '신용 점수 상시 +100 · (장착) B형 DC -3'),
  'ACH_004': TitleDef('ACH_004', '기생초', '대륙의 파산자', '4등급 대출 이자 누적 할증 -5%'),
  'ACH_BOSS': TitleDef('ACH_BOSS', '대륙의 절대 포식자', '진 보스 격파', '의장 네오 맹수 격파의 증표'),
};

// =============================================================================
//  [Model] 돌발 뉴스
// =============================================================================
class NewsDef {
  final String code, title, effectDesc, successDesc;
  final int minTurn, respondDc;
  final TribeStat? respondStat;
  const NewsDef(this.code, this.title, this.minTurn, this.effectDesc,
      this.respondStat, this.respondDc, this.successDesc);
}

const List<NewsDef> kNews = [
  NewsDef('NS_003', '원시 꿀송이 거품 붕괴', 2, '암시장 장비 매입가 30% 폭락',
      TribeStat.wildness, 13, '자본 이득 +10,000 스톤'),
  NewsDef('NS_001', '그림자 의회의 기습 금리 인상', 3, '다음 3턴 대출 이자율 2배 할증',
      TribeStat.leather, 15, '유지비 30% 감면(즉시 1턴)'),
  NewsDef('NS_004', '의회 내부자의 기밀 유출', 5, '다음 1턴 A·C형 요구 DC -3 경감',
      null, 0, '글로벌 보너스 버프 작동'),
  NewsDef('NS_002', '검은 목요일의 대공황', 6, '즉시 마나 스톤 잔액 15% 강제 삭감',
      TribeStat.influence, 17, '자산 삭감 0% 면제'),
];

// =============================================================================
//  [Data] 타이니 충성 NPC 대사
// =============================================================================
class Tiny {
  const Tiny._();
  static const Map<ChoiceType, String> success = {
    ChoiceType.aggressive:
        '대장님! 시장의 모든 나약한 초식동물들이 대장님의 거침없는 야성에 짓눌려 '
            '비명을 지르고 있습니다! 이 막대한 자산은 전부 대장님의 몫입니다!',
    ChoiceType.conservative:
        '소름 돋을 정도로 완벽한 안목이십니다, 대장님. 의회의 능구렁이 같은 고위 '
            '관료들조차 대장님의 완벽한 자산 설계 앞에 무릎을 꿇었습니다!',
    ChoiceType.shortSale:
        '대륙의 역사가 바뀝니다!! 모두가 파멸할 때 홀로 세상을 비웃으며 거부로 '
            '군림하는 자, 그게 바로 대장님이십니다! 소름이 멈추지 않습니다!',
    ChoiceType.transcend:
        '초월하셨습니다, 대장님!! 의회의 시스템 그 자체를 손아귀에 넣으신 '
            '대륙 유일의 신이시여! 제 충성을 영원히 바치겠습니다!',
  };
  static const String critical =
      '방금 그 주사위는 신의 계시였습니다! 대장님의 매서운 손끝을 대륙 전체가 '
      '두려워하고 있습니다! 지금 당장 한 번 더 진격하시죠!';
  static const String fail =
      '대장님, 고개를 숙이지 마십시오! 의회가 파놓은 비열한 함정에 잠시 발을 '
      '헛디뎠을 뿐입니다. 대장님의 매서운 발톱은 아직 부러지지 않았습니다!';
  static const String crisis =
      '이대로 대륙의 영웅이 자본의 노예들에게 무릎 꿇는 서사를 용납할 수 없습니다...! '
      '대장님, 의회의 자금줄을 역으로 묶어버릴 마지막 카드가 준비되어 있습니다!';
  static const Map<String, String> domain = {
    '원시 부족': '대장님, 지금은 비록 초라하지만 대장님의 야성이라면 이 대륙을 집어삼킬 날이 머지않았습니다!',
    '상단 거점': '보십시오, 대장님! 대륙의 모든 상권이 대장님의 손끝에서 움직이기 시작했습니다. 진정한 거상이십니다!',
    '황금 제국': '중앙 의회의 고위 관료들이 대장님의 알현을 받기 위해 줄을 섰습니다. 대장님은 대륙의 영원한 태양이십니다!',
  };
  static const String huntWin = '깔끔한 사냥이었습니다, 대장님! 약탈한 전리품에서 피 냄새가 향긋합니다!';
  static const String huntLose = '잠시 발톱을 다쳤을 뿐입니다. 다음 사냥감은 반드시 대장님의 먹잇감이 됩니다!';
  static const String idle = '대장님, 다음 사냥감이 코앞입니다. 발톱을 휘두를 준비만 하십시오!';
  static const String levelUp = '대장님의 격이 한 단계 올라섰습니다! 적들의 떨림이 여기까지 느껴집니다!';
  static const String bossWin =
      '역사가 대장님의 이름을 영원히 기억할 것입니다. 보이지 않는 손을 꺾은 최초의 정복자, 대장 만세!!';
  static const String wealth =
      '이제 중앙 의회조차 대장님의 그림자 아래 숨 죽이고 있습니다. 이 대륙의 진짜 주인은 오직 대장님뿐입니다!';

  // ── v8 확장 대사 풀 (랜덤) ──
  // 사건 진입 시 (평상 톤)
  static const List<String> storyIntro = [
    '대장님, 다음 먹잇감이 어슬렁거립니다. 망설이면 놓칩니다 — 발톱부터 세우시죠!',
    '제 코끝에 돈 냄새가 진동합니다. 이번 건도 분명 대박입니다, 대장님!',
    '의회 놈들이 또 수작을 부리는군요. 대장님의 야성으로 짓밟아 버리시죠!',
    '긴장하실 것 없습니다. 대장님 손끝 하나에 대륙이 떱니다.',
    '자, 어느 길로 가시겠습니까? 어느 쪽이든 제가 끝까지 보좌하겠습니다!',
  ];
  // 1회차 가이드 톤 (콕 집어줌)
  static const List<String> guide = [
    '고민 마십시오 대장님! ⭐ 표시된 길이 정답입니다. 제 직감을 믿으세요!',
    '이번엔 ⭐ 쪽으로 시원하게 들이받으시죠! 제가 길을 압니다!',
    '복잡하게 생각 마세요. ⭐ 누르고 승리의 쾌감만 즐기십시오!',
    '대장님은 즐기기만 하십시오. ⭐ 따라가면 만사형통입니다!',
  ];
  // 실패 격려
  static const List<String> failPool = [
    '대장님, 고개 드십시오! 발톱 한 번 헛디뎠을 뿐, 아직 부러지지 않았습니다!',
    '괜찮습니다! 진짜 맹수는 한두 번 넘어진다고 사냥을 멈추지 않습니다!',
    '의회의 비열한 함정입니다. 이건 대장님 잘못이 아닙니다 — 다음엔 본때를!',
    '잠깐 피를 봤을 뿐입니다. 상처는 맹수를 더 사납게 만들 뿐이죠!',
    '제가 곁에 있습니다, 대장님. 한 번 더 가시죠. 이번엔 다릅니다!',
  ];
  // 실수 후 성공 (컴백 — 가장 크게 환호)
  static const List<String> comeback = [
    '크하핫!! 보셨습니까!! 넘어졌다가 더 무섭게 일어서는 게 진짜 맹수입니다, 대장님!!',
    '바로 이겁니다!! 실패는 대장님을 담금질했을 뿐!! 완벽한 복수입니다!!',
    '소름이 돋습니다 대장님!! 위기를 카타르시스로 뒤집는 분은 대장님뿐입니다!!',
    '의회 놈들 표정 보십니까?! 무너진 줄 알았던 맹수가 송곳니를 드러냈습니다!!',
  ];
  // 연속 성공 (뽕 가중)
  static const List<String> streak = [
    '멈출 수가 없습니다 대장님!! 이 기세 그대로 대륙을 통째로 삼키시죠!!',
    '연승입니다!! 대장님 앞에 감히 맞설 부족이 남아있긴 합니까?!',
    '대장님의 손끝에서 황금이 비처럼 쏟아집니다!! 이게 정복의 맛이죠!!',
  ];
  // 잭팟 (예측불가 대박)
  static const List<String> jackpot = [
    '대박입니다 대장님!!! 금고가 터져나갑니다!! 이건 신도 시샘할 행운입니다!!',
    '으하하핫!! 하늘이 대장님께 황금 비를 퍼붓습니다!! 잭팟이다아아!!',
    '믿기십니까 대장님?! 한 방에 금고가 두 배로 부풀었습니다!! 전설입니다!!',
  ];
  // 니어미스 (한 끗 차이 실패 — 재도전 충동 자극)
  static const List<String> nearMiss = [
    '아아악!! 딱 한 끗이었습니다 대장님!! 이건 거의 이긴 겁니다, 한 번만 더!!',
    '손끝에서 미끄러졌습니다... 정말 아슬아슬했어요! 다음 판은 무조건 대장님 겁니다!',
    '의회 놈들이 운으로 겨우 막았습니다! 이렇게 가까웠는데, 한 번 더 가시죠!!',
  ];

  static String pick(List<String> pool, Random r) => pool[r.nextInt(pool.length)];
}

// =============================================================================
//  [Model] 선택지 / 이벤트 / 결과 / 보스
// =============================================================================
class GameOption {
  final ChoiceType type;
  final String successText, failText;
  final int goldSuccess, goldFail, expSuccess;
  final String? itemReward;
  final Map<TribeStat, int> statFail;
  final int creditFail;
  final bool isEnding;
  final String? endingTitle, endingAchievement;
  final bool isHiddenS, sFailGameOver;
  const GameOption({
    required this.type,
    this.successText = '',
    this.failText = '',
    this.goldSuccess = 0,
    this.goldFail = 0,
    this.expSuccess = 0,
    this.itemReward,
    this.statFail = const {},
    this.creditFail = 0,
    this.isEnding = false,
    this.endingTitle,
    this.endingAchievement,
    this.isHiddenS = false,
    this.sFailGameOver = false,
  });
}

class GameEvent {
  final String id;
  final int chapter;
  final String title, mainText;
  final List<GameOption> options;
  const GameEvent({
    required this.id,
    required this.chapter,
    required this.title,
    required this.mainText,
    required this.options,
  });
}

class DiceResult {
  final int rawRoll, effectiveRoll, statModifier, extraModifier, finalValue, dc;
  final DiceOutcome outcome;
  final double payoutMul;
  final bool hyperApplied, mythicApplied;
  const DiceResult(this.rawRoll, this.effectiveRoll, this.statModifier,
      this.extraModifier, this.finalValue, this.dc, this.outcome, this.payoutMul,
      this.hyperApplied, this.mythicApplied);
}

class BossPhaseDef {
  final String name;
  final TribeStat stat;
  final int dc;
  final String penalty;
  const BossPhaseDef(this.name, this.stat, this.dc, this.penalty);
}

const List<BossPhaseDef> kBossPhases = [
  BossPhaseDef('1단계 · 통화 압착 (금리 인상 폭탄)', TribeStat.leather, 18, '마나 스톤 -20,000'),
  BossPhaseDef('2단계 · 평판 말소 (가짜 뉴스 선동)', TribeStat.influence, 20, '신용 등급 2단계 강제 하락'),
  BossPhaseDef('3단계 · 무력 처분 (용병단 총공격)', TribeStat.wildness, 22, '최고 등급 장비 파괴'),
];

// =============================================================================
//  [Data] 메인 스크립트 (SCR_001~012)
// =============================================================================
class GameScript {
  const GameScript._();
  static GameEvent byId(String id) => _map[id]!;
  static final Map<String, GameEvent> _map = {for (final e in all) e.id: e};

  static const List<GameEvent> all = [
    GameEvent(id: 'SCR_001', chapter: 1, title: '01. 황금빛 꿀송이의 유혹',
      mainText: '남쪽 계곡에서 기이한 황금빛 꿀송이가 발견되었습니다. '
          '대륙의 모든 부족이 군침을 흘리며 몰려들고 있습니다…',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '승부수가 통했습니다! 선점한 계곡 구역에서 꿀송이가 쏟아집니다.',
          failText: '재앙이 가로막습니다. 끌어모아 차지한 땅은 메말랐습니다.',
          goldSuccess: 5000, expSuccess: 150, itemReward: '일반 벨트',
          goldFail: -1500, statFail: {TribeStat.leather: -2}, creditFail: -1),
        GameOption(type: ChoiceType.conservative,
          successText: '현명한 계산이 빛을 발합니다. 길목에 초소를 세워 통행세를 거둡니다.',
          failText: '판단이 늦었습니다. 하이에나 부족이 우회로를 뚫습니다.',
          goldSuccess: 2000, expSuccess: 100,
          goldFail: -500, statFail: {TribeStat.influence: -1}),
        GameOption(type: ChoiceType.shortSale,
          successText: '대륙의 역사가 대장님의 혜안 앞에 무릎을 꿇습니다.',
          failText: '작전 실패, 시장이 이성을 상실해 가격이 거꾸로 치솟습니다.',
          goldSuccess: 12000, expSuccess: 300, itemReward: '고대 대검',
          goldFail: -8000, statFail: {TribeStat.leather: -4}),
      ]),
    GameEvent(id: 'SCR_002', chapter: 1, title: '02. 그림자 위원회의 보증서',
      mainText: '광기가 절정에 달하자, 기묘한 양가죽 증서를 그림자 위원회가 흩뿌립니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '완벽한 타이밍에 폭탄을 넘겼습니다! 최고점에서 털어냈습니다.',
          failText: '최고점에 물렸습니다! 발행량을 10배로 늘린다는 소문이 돕니다.',
          goldSuccess: 7500, expSuccess: 180,
          goldFail: -3000, statFail: {TribeStat.wildness: -2}),
        GameOption(type: ChoiceType.conservative,
          successText: '기밀 정보를 선점했습니다! 마법 문자를 해독해 길목을 잡았습니다.',
          failText: '의회의 역공을 받았습니다. 시장 교란죄 혐의를 뒤집어씁니다.',
          goldSuccess: 3500, expSuccess: 140, itemReward: '희귀 실크햇',
          goldFail: -1000, statFail: {TribeStat.influence: -2}),
        GameOption(type: ChoiceType.shortSale,
          successText: '대륙의 질서를 뒤흔드는 대승리입니다!',
          failText: '보이지 않는 손에 짓밟혔습니다! 가격을 억지로 부양당합니다.',
          goldSuccess: 15000, expSuccess: 350, itemReward: '고대 대검',
          goldFail: -9900, creditFail: -2),
      ]),
    GameEvent(id: 'SCR_003', chapter: 1, title: '03. 꽃망울이 터지는 날',
      mainText: '꿀송이가 창고에서 무더기로 썩어간다는 밀서가 도착했습니다. 거품이 터지기 직전입니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '기적이 일어났습니다! 의회의 기습 부양책으로 반등합니다.',
          failText: '완벽한 파멸입니다. 떨어지는 칼날을 맨손으로 잡았습니다.',
          goldSuccess: 9000, expSuccess: 200,
          goldFail: -5000, statFail: {TribeStat.wildness: -3}),
        GameOption(type: ChoiceType.conservative,
          successText: '탈출에 성공했습니다! 무너지기 전 헐값에 모두 넘겼습니다.',
          failText: '처분 타이밍을 놓쳤습니다. 매수자가 전멸했습니다.',
          goldSuccess: 4000, expSuccess: 150,
          goldFail: -2000, statFail: {TribeStat.influence: -2}),
        GameOption(type: ChoiceType.shortSale,
          successText: '전설적인 대청산의 날입니다! 공매도 계약이 만개합니다.',
          failText: '리스크 맷집이 버티지 못했습니다! 규제로 계약이 무효화됩니다.',
          goldSuccess: 25000, expSuccess: 500, itemReward: '신화 무기 해금',
          goldFail: -15000, statFail: {TribeStat.leather: -5}),
      ]),
    GameEvent(id: 'SCR_004', chapter: 2, title: '04. 도미노 파산의 서막',
      mainText: '리먼 행성단이 파산을 선언했습니다. 뱅크런 사태가 대륙을 덮칩니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '포식자의 약탈이 통했습니다! 부도 영토를 헐값에 집어삼킵니다.',
          failText: '타이밍이 일렀습니다. 숨겨진 부채가 연쇄로 터집니다.',
          goldSuccess: 6000, expSuccess: 220, itemReward: '희귀 문서',
          goldFail: -4000, statFail: {TribeStat.wildness: -2}),
        GameOption(type: ChoiceType.conservative,
          successText: '신뢰의 승리입니다! 자산 구조를 공개해 동요를 잠재웁니다.',
          failText: '부족원들의 패닉을 막지 못했습니다. 뱅크런이 번집니다.',
          goldSuccess: 3000, expSuccess: 180, itemReward: '일반 방패',
          goldFail: -2500, statFail: {TribeStat.influence: -3}),
        GameOption(type: ChoiceType.shortSale,
          successText: '차가운 송곳니가 흑막을 뚫었습니다! 공매도가 만료 정산됩니다.',
          failText: '의회의 기습 구제금융 선언으로 강제 청산당합니다.',
          goldSuccess: 18000, expSuccess: 400, itemReward: '고대 무기',
          goldFail: -12000, statFail: {TribeStat.leather: -4}),
      ]),
    GameEvent(id: 'SCR_005', chapter: 2, title: '05. 보이지 않는 손의 개입',
      mainText: '중앙 의회가 무제한으로 공짜 마나를 살포하겠다고 선언했습니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '트렌드를 관통했습니다! 지원금을 끌어와 희귀 원석을 선점합니다.',
          failText: '타이밍을 놓쳤습니다! 경쟁하느라 수수료만 날립니다.',
          goldSuccess: 8000, expSuccess: 250,
          goldFail: -3000, statFail: {TribeStat.wildness: -2}),
        GameOption(type: ChoiceType.conservative,
          successText: '완벽한 방어전입니다! 자산을 실물 고대 금괴로 전환합니다.',
          failText: '가짜 금괴에 속았습니다! 사기꾼에게 고철을 떠안습니다.',
          goldSuccess: 4500, expSuccess: 200, itemReward: '일반 방패',
          goldFail: -2000, statFail: {TribeStat.influence: -3}),
        GameOption(type: ChoiceType.shortSale,
          successText: '의회의 오판을 징벌했습니다! 폭락을 정확히 저격합니다.',
          failText: '규제에 막혔습니다! 매매 정지로 자산이 동결됩니다.',
          goldSuccess: 20000, expSuccess: 450, itemReward: '고대 무기',
          goldFail: -14000, statFail: {TribeStat.leather: -5}),
      ]),
    GameEvent(id: 'SCR_006', chapter: 2, title: '06. 구조조정의 칼바람',
      mainText: '부족의 유지비를 갉아먹는 거대 전투수들을 어찌할지 결단할 때입니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '맹수의 본능 증명! 몬스터 영토를 무자비하게 침공합니다.',
          failText: '전멸에 가까운 타격! 전투수들이 폭주해 패퇴합니다.',
          goldSuccess: 10000, expSuccess: 280,
          goldFail: -6000, statFail: {TribeStat.wildness: -3}),
        GameOption(type: ChoiceType.conservative,
          successText: '현명한 슬림화! 전투수를 방출해 고정비를 줄입니다.',
          failText: '청산 타이밍을 놓쳤습니다! 유지비가 금고를 파먹습니다.',
          goldSuccess: 5500, expSuccess: 220, itemReward: '희귀 문서',
          goldFail: -3500, statFail: {TribeStat.influence: -2}),
        GameOption(type: ChoiceType.shortSale,
          successText: '탐욕스러운 포식 완수! 부도 자산을 압도적 맷집으로 흡수합니다.',
          failText: '맷집 한계 초과! 독소 조항이 터집니다.',
          goldSuccess: 22000, expSuccess: 500, itemReward: '고대 무기',
          goldFail: -16000, statFail: {TribeStat.leather: -5}, creditFail: -1),
      ]),
    GameEvent(id: 'SCR_007', chapter: 3, title: '07. 마법 공학 엔진의 탄생',
      mainText: '마법 공학 엔진이 발명되었습니다. 이름만 같으면 폭등하는 묻지마 광풍이 붑니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '광기의 파도를 탔습니다! 최고점에서 유령 지분을 떠넘깁니다.',
          failText: '막차를 탔습니다! 유령 부족들이 연쇄로 야반도주합니다.',
          goldSuccess: 12000, expSuccess: 320, itemReward: '일반 부츠',
          goldFail: -5000, statFail: {TribeStat.wildness: -3}),
        GameOption(type: ChoiceType.conservative,
          successText: '안목의 승리! 정식 특허를 가진 우량 부족을 선별 투자합니다.',
          failText: '가짜 검증에 속아 사기꾼 부족에게 예산을 기부합니다.',
          goldSuccess: 6000, expSuccess: 250, itemReward: '희귀 돋보기',
          goldFail: -3000, statFail: {TribeStat.influence: -2}),
        GameOption(type: ChoiceType.shortSale,
          successText: '시대를 앞서간 매도자! 사기극을 확신하고 대규모 공매도를 칩니다.',
          failText: '광기에 압사! 의회 선동으로 폭등해 마진콜로 청산됩니다.',
          goldSuccess: 24000, expSuccess: 550, itemReward: '고대 무기',
          goldFail: -18000, statFail: {TribeStat.leather: -5}, creditFail: -1),
      ]),
    GameEvent(id: 'SCR_008', chapter: 3, title: '08. 트렌드의 지배자',
      mainText: '대륙 통신망 플랫폼을 구축하는 독점 주도권 전쟁이 벌어집니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '거대 플랫폼 주인 등극! 경쟁 부족을 치킨게임으로 파산시킵니다.',
          failText: '과도한 빚에 짓눌려 매달 돌아오는 이자에 비틀거립니다.',
          goldSuccess: 15000, expSuccess: 350, itemReward: '일반 부츠',
          goldFail: -6500, statFail: {TribeStat.wildness: -3}, creditFail: -1),
        GameOption(type: ChoiceType.conservative,
          successText: '완벽한 설계! 보안 표준을 제정하고 통행세를 징수합니다.',
          failText: '규제의 덫! 독점 금지 소송에 휘말려 비용을 쏟습니다.',
          goldSuccess: 8000, expSuccess: 280, itemReward: '희귀 돋보기',
          goldFail: -4000, statFail: {TribeStat.influence: -3}),
        GameOption(type: ChoiceType.shortSale,
          successText: '독점의 숨통을 끊음! 취약점을 간파해 마비시킵니다.',
          failText: '독점 권력의 보복! 역추적당해 계정이 동결됩니다.',
          goldSuccess: 28000, expSuccess: 600, itemReward: '고대 무기',
          goldFail: -20000, statFail: {TribeStat.leather: -5}),
      ]),
    GameEvent(id: 'SCR_009', chapter: 3, title: '09. 프로토콜 거품의 종말',
      mainText: '신기술 부족들의 금고가 바닥났습니다. 연쇄 하한가로 버블이 붕괴합니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '진정한 가치 투자! 투매가 쏟아질 때 뚝심으로 주워 담습니다.',
          failText: '떨어지는 칼날에 피범벅! 지하실을 뚫고 추락합니다.',
          goldSuccess: 18000, expSuccess: 400, itemReward: '일반 부츠',
          goldFail: -8000, statFail: {TribeStat.wildness: -4}),
        GameOption(type: ChoiceType.conservative,
          successText: '위기 관리 정석! 지분을 신속 투매해 순수 스톤을 확보합니다.',
          failText: '미련을 못 버려 시스템 마비로 전 자산이 묶입니다.',
          goldSuccess: 10000, expSuccess: 300, itemReward: '희귀 돋보기',
          goldFail: -5000, statFail: {TribeStat.influence: -3}),
        GameOption(type: ChoiceType.shortSale,
          successText: '역사적 대포식! 폭락 최저점에서 공매도를 완벽 청산합니다.',
          failText: '시스템 농간! 의회가 공매도를 전면 금지해 담보를 몰수합니다.',
          goldSuccess: 35000, expSuccess: 700, itemReward: '고대 무기',
          goldFail: -22000, statFail: {TribeStat.leather: -5}, creditFail: -1),
      ]),
    GameEvent(id: 'SCR_010', chapter: 4, title: '10. 그림자 의회의 전면전',
      mainText: '흑막 그림자 의회가 전면 자산 동결과 시장 조작을 개시했습니다. 대륙의 명운을 건 전면전입니다.',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '맹수의 역습 성공! 의회 비밀 금고를 직접 타격해 동결을 해제합니다.',
          failText: '자본의 요새 정예 용병단의 반격에 전투수들이 궤멸합니다.',
          goldSuccess: 25000, expSuccess: 500, itemReward: '신화 왕관 해금',
          goldFail: -12000, statFail: {TribeStat.wildness: -4}),
        GameOption(type: ChoiceType.conservative,
          successText: '정의의 심판! 주변 부족들을 규합해 최고 법정에 고발합니다.',
          failText: '배신자 발생! 의회 매수에 넘어간 자에게 밀고당해 기각됩니다.',
          goldSuccess: 15000, expSuccess: 420, itemReward: '신화 반지 해금',
          goldFail: -7500, statFail: {TribeStat.influence: -4}, creditFail: -1),
        GameOption(type: ChoiceType.shortSale,
          successText: '시스템 파멸 설계! 조작 자산의 취약점에 역공매도 폭탄을 던집니다.',
          failText: '거대 자본의 무한 매수 조작에 감당 못 하고 청산됩니다.',
          goldSuccess: 45000, expSuccess: 800, itemReward: '신화 장비 2종',
          goldFail: -30000, statFail: {TribeStat.leather: -6}),
      ]),
    GameEvent(id: 'SCR_011', chapter: 4, title: '11. 마지막 검은 목요일',
      mainText: '의회가 대규모 인위적 폭락을 유도합니다. 대공황의 심장부에서 대장님의 선택은?',
      options: [
        GameOption(type: ChoiceType.aggressive,
          successText: '"위기는 곧 기회!" 폭락한 의회 핵심 자산을 통째로 흡수해 실질적 지배자로 섰습니다.',
          failText: '떨어지는 칼날에 심장이 뚫렸습니다. 전 자산이 바닥을 뚫고 증발합니다.',
          goldSuccess: 30000, expSuccess: 600, itemReward: '신화 무기 해금',
          goldFail: -15000, statFail: {TribeStat.wildness: -4}),
        GameOption(type: ChoiceType.conservative,
          successText: '완벽한 회피! 모든 화폐 자산을 고대 성벽에 숨겨 피해를 제로로 방어합니다.',
          failText: '한발 늦었습니다. 규제 수수료가 금고를 들이받습니다.',
          goldSuccess: 10000, expSuccess: 450,
          goldFail: -5000, statFail: {TribeStat.influence: -3}),
        GameOption(type: ChoiceType.shortSale,
          successText: "전설적인 '빅쇼트'의 완성! 마지막 포지션이 정점에서 폭발하며 신의 반열에 오릅니다.",
          failText: '의회가 초법적 셧다운을 감행하며 금고가 완전히 파산합니다.',
          goldSuccess: 60000, expSuccess: 900, itemReward: '신화 반지 즉시 지급',
          goldFail: -35000, statFail: {TribeStat.leather: -6}, creditFail: -1),
        GameOption(type: ChoiceType.transcend, isHiddenS: true, sFailGameOver: true,
          successText: '[초월적 흡수] 시스템의 허점을 역으로 장악, 대륙의 모든 통화 발행 권한을 '
              '뺏어와 의회를 하급 부족으로 강등시킵니다.',
          failText: '[역풍의 종말] 의회의 숨겨진 양자 연산을 간파하지 못해 역공당하고, '
              '부족의 존재가 대륙 역사에서 영구 말소됩니다.',
          goldSuccess: 100000, expSuccess: 1500, itemReward: '신화 타이거 엠페러 슈트 지급'),
      ]),
    GameEvent(id: 'SCR_012', chapter: 4, title: '12. 보이지 않는 손의 종말',
      mainText: '의회를 무너뜨린 후, 대륙의 새로운 질서를 확립하는 최종 분기입니다. 대장님의 철학은?',
      options: [
        GameOption(type: ChoiceType.aggressive, isEnding: true,
          endingTitle: '엔딩 A · 황금 왕좌의 맹수', endingAchievement: '독점 지배자',
          successText: '새로운 의회의 주인이 되어 대륙의 모든 힘과 자원을 완벽하게 독점 지배하는 제왕이 됩니다.'),
        GameOption(type: ChoiceType.conservative, isEnding: true,
          endingTitle: '엔딩 B · 대륙의 수호자', endingAchievement: '평화주의자',
          successText: '공공 신용 조합을 설립하여 모든 부족이 공평하게 마나를 나누는 상생의 시대를 엽니다.'),
        GameOption(type: ChoiceType.shortSale, isEnding: true,
          endingTitle: '엔딩 C · 원시 야생으로', endingAchievement: '자연주의자',
          successText: '모든 화폐와 신용 시스템을 화산에 던져 파괴하고, 순수 원시 야생으로 회귀합니다.'),
      ]),
  ];
}

// =============================================================================
//  [Model] player_state
// =============================================================================
class PlayerState {
  final int turn, bloodGold, creditGrade, creditScore, level, exp;
  final Map<TribeStat, int> stats;
  final String currentRegion;
  final Set<String> unlockedRegions, completedEvents;
  final List<Equipment> bag;
  final Map<EquipSlot, Equipment?> equipped;
  final Set<String> titles;
  final String activeTitle;
  final Set<String> relics; // 보유 유물(영구 패시브)
  final bool bankruptcyActive;
  final int graceRemaining, delinquentStreak;
  final bool raidLocked, gameOver, cleared;
  final String endingTitle, endingAchievement;
  final int interestPenaltyTurns, acDcReliefTurns;
  final int cShortWinStreak, newsLeatherDefenseStreak;
  final int huntWins, totalEarned;

  const PlayerState({
    required this.turn,
    required this.bloodGold,
    required this.creditGrade,
    required this.creditScore,
    required this.stats,
    required this.currentRegion,
    required this.unlockedRegions,
    required this.completedEvents,
    required this.level,
    required this.exp,
    this.bag = const [],
    this.equipped = const {},
    this.titles = const {},
    this.activeTitle = '',
    this.relics = const {},
    this.bankruptcyActive = false,
    this.graceRemaining = 0,
    this.delinquentStreak = 0,
    this.raidLocked = false,
    this.gameOver = false,
    this.cleared = false,
    this.endingTitle = '',
    this.endingAchievement = '',
    this.interestPenaltyTurns = 0,
    this.acDcReliefTurns = 0,
    this.cShortWinStreak = 0,
    this.newsLeatherDefenseStreak = 0,
    this.huntWins = 0,
    this.totalEarned = 0,
  });

  factory PlayerState.newGame() => PlayerState(
        turn: 1, bloodGold: 10000, creditGrade: 2, creditScore: 700,
        stats: const {
          TribeStat.wildness: 10,
          TribeStat.influence: 10,
          TribeStat.leather: 10,
        },
        currentRegion: 'valley',
        unlockedRegions: {...kInitialRegions},
        completedEvents: const {},
        level: 1, exp: 0,
      );

  // ── 세이브 직렬화 ──
  Map<String, dynamic> toJson() => {
        'turn': turn, 'gold': bloodGold, 'cg': creditGrade, 'cs': creditScore,
        'lv': level, 'exp': exp,
        'stats': stats.map((k, v) => MapEntry(k.index.toString(), v)),
        'region': currentRegion,
        'unlocked': unlockedRegions.toList(),
        'completed': completedEvents.toList(),
        'bag': bag.map((e) => e.toJson()).toList(),
        'equipped': {
          for (final s in EquipSlot.values)
            s.index.toString(): equipped[s]?.toJson(),
        },
        'titles': titles.toList(),
        'activeTitle': activeTitle,
        'relics': relics.toList(),
        'bk': bankruptcyActive, 'grace': graceRemaining, 'delin': delinquentStreak,
        'lock': raidLocked, 'over': gameOver, 'clear': cleared,
        'et': endingTitle, 'ea': endingAchievement,
        'ipt': interestPenaltyTurns, 'acr': acDcReliefTurns,
        'csw': cShortWinStreak, 'nld': newsLeatherDefenseStreak,
        'hw': huntWins, 'te': totalEarned,
      };

  static PlayerState fromJson(Map<String, dynamic> j) {
    final st = <TribeStat, int>{};
    (j['stats'] as Map).forEach((k, v) {
      st[TribeStat.values[int.parse(k as String)]] = v as int;
    });
    final eq = <EquipSlot, Equipment?>{};
    (j['equipped'] as Map).forEach((k, v) {
      eq[EquipSlot.values[int.parse(k as String)]] =
          v == null ? null : Equipment.fromJson((v as Map).cast<String, dynamic>());
    });
    return PlayerState(
      turn: j['turn'] as int, bloodGold: j['gold'] as int,
      creditGrade: j['cg'] as int, creditScore: j['cs'] as int,
      level: j['lv'] as int, exp: j['exp'] as int,
      stats: st,
      currentRegion: j['region'] as String,
      unlockedRegions: (j['unlocked'] as List).map((e) => e as String).toSet(),
      completedEvents: (j['completed'] as List).map((e) => e as String).toSet(),
      bag: (j['bag'] as List)
          .map((e) => Equipment.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      equipped: eq,
      titles: (j['titles'] as List).map((e) => e as String).toSet(),
      activeTitle: j['activeTitle'] as String,
      relics: (j['relics'] as List?)?.map((e) => e as String).toSet() ?? <String>{},
      bankruptcyActive: j['bk'] as bool, graceRemaining: j['grace'] as int,
      delinquentStreak: j['delin'] as int,
      raidLocked: j['lock'] as bool, gameOver: j['over'] as bool,
      cleared: j['clear'] as bool,
      endingTitle: j['et'] as String, endingAchievement: j['ea'] as String,
      interestPenaltyTurns: j['ipt'] as int, acDcReliefTurns: j['acr'] as int,
      cShortWinStreak: j['csw'] as int, newsLeatherDefenseStreak: j['nld'] as int,
      huntWins: j['hw'] as int, totalEarned: j['te'] as int,
    );
  }

  bool get mythicEquipped => equipped[EquipSlot.mythic]?.isMythicSuit ?? false;

  int effectiveStat(TribeStat s) {
    int v = stats[s] ?? 0;
    for (final e in equipped.values) {
      if (e != null) v += e.statBonus[s] ?? 0;
    }
    return v;
  }

  int statOf(TribeStat s) => stats[s] ?? 0;
  int get statTotal => TribeStat.values.fold(0, (a, s) => a + effectiveStat(s));

  bool get sUnlocked =>
      statTotal >= Cfg.sUnlockStatTotal &&
      creditGrade <= 1 &&
      bloodGold >= Cfg.sUnlockGold;

  String get domainStage => bloodGold >= 300000
      ? '황금 제국'
      : bloodGold >= 50000
          ? '상단 거점'
          : '원시 부족';

  String get portrait {
    if (level >= 5) return '👑🐯';
    if (bloodGold >= 300000) return '👑';
    if (level >= 3) return '🦁';
    return '🐯';
  }

  bool regionQuestsCleared(String regionId) {
    final r = kRegions[regionId];
    if (r == null || r.questEventIds.isEmpty) return true;
    return r.questEventIds.every(completedEvents.contains);
  }

  String? nextQuestOf(String regionId) {
    final r = kRegions[regionId];
    if (r == null) return null;
    for (final id in r.questEventIds) {
      if (!completedEvents.contains(id)) return id;
    }
    return null;
  }

  PlayerState copyWith({
    int? turn,
    int? bloodGold,
    int? creditGrade,
    int? creditScore,
    Map<TribeStat, int>? stats,
    String? currentRegion,
    Set<String>? unlockedRegions,
    Set<String>? completedEvents,
    int? level,
    int? exp,
    List<Equipment>? bag,
    Map<EquipSlot, Equipment?>? equipped,
    Set<String>? titles,
    String? activeTitle,
    Set<String>? relics,
    bool? bankruptcyActive,
    int? graceRemaining,
    int? delinquentStreak,
    bool? raidLocked,
    bool? gameOver,
    bool? cleared,
    String? endingTitle,
    String? endingAchievement,
    int? interestPenaltyTurns,
    int? acDcReliefTurns,
    int? cShortWinStreak,
    int? newsLeatherDefenseStreak,
    int? huntWins,
    int? totalEarned,
  }) =>
      PlayerState(
        turn: turn ?? this.turn,
        bloodGold: bloodGold ?? this.bloodGold,
        creditGrade: creditGrade ?? this.creditGrade,
        creditScore: creditScore ?? this.creditScore,
        stats: stats ?? this.stats,
        currentRegion: currentRegion ?? this.currentRegion,
        unlockedRegions: unlockedRegions ?? this.unlockedRegions,
        completedEvents: completedEvents ?? this.completedEvents,
        level: level ?? this.level,
        exp: exp ?? this.exp,
        bag: bag ?? this.bag,
        equipped: equipped ?? this.equipped,
        titles: titles ?? this.titles,
        activeTitle: activeTitle ?? this.activeTitle,
        relics: relics ?? this.relics,
        bankruptcyActive: bankruptcyActive ?? this.bankruptcyActive,
        graceRemaining: graceRemaining ?? this.graceRemaining,
        delinquentStreak: delinquentStreak ?? this.delinquentStreak,
        raidLocked: raidLocked ?? this.raidLocked,
        gameOver: gameOver ?? this.gameOver,
        cleared: cleared ?? this.cleared,
        endingTitle: endingTitle ?? this.endingTitle,
        endingAchievement: endingAchievement ?? this.endingAchievement,
        interestPenaltyTurns: interestPenaltyTurns ?? this.interestPenaltyTurns,
        acDcReliefTurns: acDcReliefTurns ?? this.acDcReliefTurns,
        cShortWinStreak: cShortWinStreak ?? this.cShortWinStreak,
        newsLeatherDefenseStreak:
            newsLeatherDefenseStreak ?? this.newsLeatherDefenseStreak,
        huntWins: huntWins ?? this.huntWins,
        totalEarned: totalEarned ?? this.totalEarned,
      );
}

// =============================================================================
//  [State] 단일화면 게임 매니저
// =============================================================================
class GameManager extends ChangeNotifier {
  final Random _random;
  PlayerState _state = PlayerState.newGame();
  Stage _stage = Stage.intro;
  Overlay _overlay = Overlay.none;

  GameEvent? activeEvent;
  DiceResult? lastResult;
  GameOption? lastOption;
  String narrative = '';
  int goldDelta = 0, expDelta = 0;
  Equipment? lastLoot;
  bool resultIsHunt = false;
  final List<String> flashes = [];
  final List<int> pendingStatChoices = [];

  // 연출
  int goldBefore = 10000;
  String tinyLine = Tiny.idle;
  bool critBanner = false;
  String critText = '';
  bool screenShake = false;
  String domainShown = '원시 부족';

  // 사냥/상점
  HuntTarget? lastHunt;
  String shopFlash = '';

  // 뉴스
  NewsDef? pendingNews;
  String newsResolveText = '';
  bool newsResolved = false;

  // 보스
  int bossPhaseIndex = 0;
  bool bossDone = false;
  DiceResult? bossLastResult;
  String bossNarrative = '';

  bool freeRoam = false;
  bool _busy = false;

  // ── v8: 회차 + 컴백 추적 ──
  int playthrough = 1; // 1회차 동안 풀가이드, 2회차부터 자유
  bool lastWasFail = false; // 직전 판정 실패 여부(컴백 감지)
  int successStreak = 0; // 연속 성공 횟수

  // ── 타이니 포커스 게이트 (타이니가 화면을 잡고 단독 발화) ──
  bool tinyFocus = false;
  void dismissTinyFocus() {
    tinyFocus = false;
    notifyListeners();
  }

  // ── 다회차 유산(메타 성장) — 패배해도 다음 회차가 강해진다 ──
  int metaStatBonus = 0, metaGoldBonus = 0;
  String legacyNote = '';

  // ── 세이브 슬롯 (3슬롯) ──
  //  ※ 다른 폰/브라우저는 localStorage가 기기마다 독립이라 자동으로 따로 저장됨.
  //    슬롯은 '같은 폰에서 둘이 번갈아' 할 때 구분용.
  static const int slotCount = 3;
  int slot = 1; // 현재 플레이 중인 슬롯
  bool _loading = false; // 로드/리셋 중 자동저장 억제
  String _key(int s) => 'auh_slot_$s';
  bool hasSlot(int s) => html.window.localStorage.containsKey(_key(s));

  // 슬롯 카드 요약(없으면 null)
  Map<String, dynamic>? slotInfo(int s) {
    final raw = html.window.localStorage[_key(s)];
    if (raw == null) return null;
    try {
      final ps = ((jsonDecode(raw) as Map)['ps'] as Map);
      return {
        'turn': ps['turn'],
        'lv': ps['lv'],
        'gold': ps['gold'],
        'region': kRegions[ps['region']]?.name ?? '?',
        'clear': ps['clear'] == true,
        'over': ps['over'] == true,
      };
    } catch (_) {
      return null;
    }
  }

  GameManager({Random? random}) : _random = random ?? Random();

  // 상태 변경 시 현재 슬롯에 자동 저장. 슬롯선택(intro)/로드 중 제외.
  @override
  void notifyListeners() {
    if (!_loading && _stage != Stage.intro) _persist();
    super.notifyListeners();
  }

  void _persist() {
    try {
      html.window.localStorage[_key(slot)] = jsonEncode({
        'ps': _state.toJson(),
        'pt': playthrough,
        'msb': metaStatBonus,
        'mgb': metaGoldBonus,
        'boss': bossDone,
        'dom': domainShown,
      });
    } catch (_) {/* 저장 실패 무시(테스트) */}
  }

  // 슬롯에서 새 게임(비우고 처음부터)
  void newSlot(int s) {
    slot = s;
    html.window.localStorage.remove(_key(s));
    _loading = true;
    _state = PlayerState.newGame();
    playthrough = 1;
    metaStatBonus = 0;
    metaGoldBonus = 0;
    legacyNote = '';
    bossDone = false;
    domainShown = '원시 부족';
    lastWasFail = false;
    successStreak = 0;
    _loading = false;
    beginAdventure();
  }

  // 슬롯 이어하기(복원 → 사건 단위 체크포인트로 진입)
  void loadSlot(int s) {
    slot = s;
    final raw = html.window.localStorage[_key(s)];
    if (raw == null) {
      newSlot(s);
      return;
    }
    _loading = true;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      _state = PlayerState.fromJson((j['ps'] as Map).cast<String, dynamic>());
      playthrough = (j['pt'] as int?) ?? 1;
      metaStatBonus = (j['msb'] as int?) ?? 0;
      metaGoldBonus = (j['mgb'] as int?) ?? 0;
      bossDone = (j['boss'] as bool?) ?? false;
      domainShown = (j['dom'] as String?) ?? _state.domainStage;
      _overlay = Overlay.none;
      if (_state.cleared) {
        _stage = Stage.ending;
      } else if (_state.gameOver) {
        _stage = Stage.gameOver;
      } else {
        _loadNextStory();
      }
    } catch (_) {
      html.window.localStorage.remove(_key(s));
      _loading = false;
      newSlot(s);
      return;
    } finally {
      _loading = false;
    }
    notifyListeners();
  }

  void deleteSlot(int s) {
    html.window.localStorage.remove(_key(s));
    notifyListeners();
  }

  // 슬롯 선택 화면(타이틀)으로 — 현재 진행은 이미 자동 저장됨
  void toSlotMenu() {
    _overlay = Overlay.none;
    _stage = Stage.intro;
    notifyListeners();
  }

  PlayerState get state => _state;
  Stage get stage => _stage;
  Overlay get overlay => _overlay;
  Region get currentRegion => kRegions[_state.currentRegion]!;

  // 1회차 전체 동안 가이드 ON (2회차 전까지 무지성 따라가기)
  bool get tutorialActive => playthrough == 1;

  String _pick(List<String> pool) => pool[_random.nextInt(pool.length)];

  bool get isHyperActive {
    if (_state.turn >= Cfg.hyperEnd) return false;
    if (_state.level >= Cfg.hyperEndLv) return false;
    return _state.turn <= Cfg.hyperLast;
  }

  static int statModifierOf(int s) => ((s - 10) / 2).floor();
  static int levelBonus(int lv) => Cfg.lvBonus[lv] ?? 0;
  static int _ci(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  int gradeFromScore(int score) {
    final eff = score + (_state.titles.contains('ACH_003') ? 100 : 0);
    if (eff >= 850) return 1;
    if (eff >= 600) return 2;
    if (eff >= 350) return 3;
    return 4;
  }

  bool get _hasHedgeClaw => _state.equipped[EquipSlot.weapon]?.id == 'SHP_003';
  bool get _hasSpyRing => _state.equipped.values.any((e) => e?.id == 'SHP_002');
  bool get _hasGamblerDice =>
      _state.equipped.values.any((e) => e?.id == 'SHP_001');

  // ── 유물 효과 합산 ──
  bool hasRelic(String id) => _state.relics.contains(id);
  num relicSum(RelicFx fx) {
    num total = 0;
    for (final id in _state.relics) {
      final r = kRelics[id];
      if (r != null && r.fx == fx) total += r.v;
    }
    return total;
  }

  // 미보유 유물 1개 랜덤 획득 + 연출
  void grantRelic({String reason = ''}) {
    final owned = _state.relics;
    final pool = kRelics.keys.where((k) => !owned.contains(k)).toList();
    if (pool.isEmpty) return;
    final id = pool[_random.nextInt(pool.length)];
    final r = kRelics[id]!;
    _state = _state.copyWith(relics: {..._state.relics, id});
    flashes.add('🏺 유물 획득: ${r.emoji} ${r.name} — ${r.desc}');
    critBanner = true;
    screenShake = true;
    critText = '🏺[유물 발굴]🏺 ${r.emoji} ${r.name}을(를) 손에 넣었습니다! ${r.desc}';
    tinyLine = '대장님!! ${r.name}입니다!! 이 힘이 영원히 대장님과 함께합니다!!';
  }

  int dcFor(ChoiceType t, int chapter) {
    if (t == ChoiceType.transcend) return Cfg.sDc;
    int dc = t.baseDc + (chapter == 3 ? 2 : (chapter >= 4 ? 5 : 0));
    if (_state.activeTitle == 'ACH_001' && t == ChoiceType.shortSale) dc -= 2;
    if (_state.activeTitle == 'ACH_003' && t == ChoiceType.conservative) dc -= 3;
    if (_state.acDcReliefTurns > 0 &&
        (t == ChoiceType.aggressive || t == ChoiceType.shortSale)) dc -= 3;
    return dc;
  }

  DiceResult _resolve(ChoiceType type, int dc, {int? forcedRaw}) {
    final hyper = isHyperActive;
    int raw = forcedRaw ?? (Cfg.diceMin + _random.nextInt(Cfg.diceMax));
    int afterMythic = raw;
    bool mythicApplied = false;
    if (_state.mythicEquipped && raw <= 5) {
      afterMythic = 6;
      mythicApplied = true;
    }
    int eff = afterMythic;
    // [유물] 맹수의 심장: 최소 눈금 +N (상시)
    final int minRollUp = relicSum(RelicFx.minRoll).toInt();
    final int floorRoll = (hyper ? Cfg.hyperMinRoll : 1) + minRollUp;
    if (eff < floorRoll) eff = floorRoll;
    int statMod = statModifierOf(_state.effectiveStat(type.stat));
    if (_hasGamblerDice && type.stat == TribeStat.wildness && statMod < 1) {
      statMod = 1;
    }
    // [유물] 포식자의 직감: 모든 판정 +N
    final extra = levelBonus(_state.level) + relicSum(RelicFx.dice).toInt();
    final finalVal = eff + statMod + extra;
    DiceOutcome outcome;
    double mul;
    if (!hyper && raw == Cfg.critFail) {
      outcome = DiceOutcome.criticalFailure;
      mul = Cfg.critFailMul;
    } else if (raw == Cfg.critSuccess) {
      outcome = DiceOutcome.criticalSuccess;
      mul = Cfg.critSuccessMul;
    } else if (hyper && (finalVal - dc) >= Cfg.hyperForceCritMargin) {
      outcome = DiceOutcome.criticalSuccess;
      mul = Cfg.critSuccessMul;
    } else if (finalVal >= dc) {
      outcome = DiceOutcome.success;
      mul = 1.0;
    } else {
      outcome = DiceOutcome.failure;
      mul = 1.0;
    }
    return DiceResult(raw, eff, statMod, extra, finalVal, dc, outcome, mul,
        hyper && eff != afterMythic, mythicApplied);
  }

  int successChance(ChoiceType type, int dc) {
    int win = 0;
    for (int r = Cfg.diceMin; r <= Cfg.diceMax; r++) {
      if (_resolve(type, dc, forcedRaw: r).outcome.isSuccess) win++;
    }
    return ((win / Cfg.diceMax) * 100).round();
  }

  static int _clampGold(int v) =>
      v > Cfg.goldMax ? Cfg.goldMax : (v < Cfg.goldMin ? Cfg.goldMin : v);

  int upkeep(int turn) {
    int cost;
    if (turn <= Cfg.upNormalLast) {
      cost = Cfg.upBase + turn * Cfg.upPer;
    } else {
      final cycles = (turn - Cfg.upNormalLast) ~/ Cfg.upCycle;
      cost = Cfg.upEndless + cycles * Cfg.upSurcharge;
    }
    if (_state.titles.contains('ACH_002')) cost = (cost * 0.9).round();
    // [유물] 불멸의 가죽: 유지비 감소
    final double up = relicSum(RelicFx.upkeep).toDouble();
    if (up > 0) cost = (cost * (1 - up)).round();
    return cost;
  }

  ChoiceType _typeForStat(TribeStat s) => s == TribeStat.wildness
      ? ChoiceType.aggressive
      : s == TribeStat.influence
          ? ChoiceType.conservative
          : ChoiceType.shortSale;
  ChoiceType typeForStat(TribeStat s) => _typeForStat(s);

  Equipment? _lootFrom(String? reward) {
    if (reward == null || reward.isEmpty) return null;
    if (reward.startsWith('신화')) return kMythicSuit;
    final g = reward.startsWith('고대')
        ? Grade.ancient
        : reward.startsWith('희귀')
            ? Grade.rare
            : Grade.common;
    EquipSlot slot = EquipSlot.accessory;
    if (reward.contains('대검') || reward.contains('무기') || reward.contains('발톱')) {
      slot = EquipSlot.weapon;
    } else if (reward.contains('벨트') ||
        reward.contains('방패') ||
        reward.contains('부츠')) {
      slot = EquipSlot.armor;
    }
    return Equipment('LOOT_${reward.hashCode}', reward, g, slot);
  }

  // ===========================================================================
  //  시작 / 사건 스트림
  // ===========================================================================
  void beginAdventure() {
    _state = _state.copyWith(currentRegion: 'valley');
    _setStory('SCR_001', keepTiny: false);
    tinyLine = '대장님, 첫 사냥감이 코앞입니다! 남쪽 황금 계곡의 꿀송이를 통째로 '
        '집어삼키시죠. 복잡한 건 전부 제게 맡기고 즐기기만 하십시오!';
    notifyListeners();
  }

  void _setStory(String id, {bool keepTiny = false}) {
    activeEvent = GameScript.byId(id);
    lastResult = null;
    lastOption = null;
    narrative = '';
    goldBefore = _state.bloodGold;
    _stage = Stage.story;
    // 사건 진입 시 타이니가 한마디 (1회차는 가이드 톤, 이후는 사건 멘트)
    if (!keepTiny) {
      tinyLine = tutorialActive ? _pick(Tiny.guide) : _pick(Tiny.storyIntro);
    }
    // 포커스 게이트: 각 지역(무대) 첫 사건에 진입할 때만 1회 — 흐름 방해 최소화.
    // (게임 시작=황금 계곡 첫 사건 = 처음 안내 / 새 지역 진입마다 1회)
    final firstOfRegion = currentRegion.questEventIds.isNotEmpty &&
        currentRegion.questEventIds.first == id;
    tinyFocus = firstOfRegion;
  }

  // 다음 사건 자동 로드 (지역 메뉴 없이 끊김없이)
  void _loadNextStory() {
    // 종장 보스 게이트
    if (currentRegion.id == 'throne' &&
        _state.completedEvents.contains('SCR_011') &&
        !bossDone &&
        !_state.completedEvents.contains('SCR_012')) {
      _startBoss();
      return;
    }
    final q = _state.nextQuestOf(currentRegion.id);
    if (q != null) {
      _setStory(q);
      return;
    }
    // 현재 지역 메인 종료 → 다음 스토리 지역으로 자동 이동
    for (final rid in kStoryOrder) {
      if (!_state.unlockedRegions.contains(rid)) continue;
      final nq = _state.nextQuestOf(rid);
      if (nq != null) {
        if (rid != currentRegion.id) {
          _state = _state.copyWith(currentRegion: rid);
          flashes.add('🗺 다음 무대로 진군: ${kRegions[rid]!.name}');
          tinyLine = '대장님, 새로운 사냥터입니다. ${kRegions[rid]!.name}을(를) 짓밟으시죠!';
        }
        if (rid == 'throne' &&
            _state.completedEvents.contains('SCR_011') &&
            !bossDone &&
            nq == 'SCR_012') {
          _startBoss();
          return;
        }
        _setStory(nq);
        return;
      }
    }
    // 모든 메인 완료
    freeRoam = true;
    _stage = Stage.story;
  }

  // ===========================================================================
  //  퀘스트 선택
  // ===========================================================================
  void choose(GameOption opt) {
    if (_busy || activeEvent == null) return;
    _busy = true;
    flashes.clear();
    lastLoot = null;
    resultIsHunt = false;
    goldBefore = _state.bloodGold;
    critBanner = false;
    screenShake = false;
    try {
      final ev = activeEvent!;
      if (opt.isEnding) {
        _state = _state.copyWith(
          cleared: true,
          completedEvents: {..._state.completedEvents, ev.id},
          endingTitle: opt.endingTitle ?? '',
          endingAchievement: opt.endingAchievement ?? '',
        );
        lastOption = opt;
        lastResult = null;
        narrative = opt.successText;
        tinyLine = Tiny.bossWin;
        _stage = Stage.ending;
        return;
      }
      if (_state.raidLocked && opt.type == ChoiceType.aggressive) {
        narrative = '⛔ 금고가 말라붙어 약탈(A형)을 감행할 수 없습니다.';
        lastResult = null;
        lastOption = opt;
        goldDelta = 0;
        expDelta = 0;
        tinyLine = Tiny.crisis;
        _stage = Stage.resolution;
        return;
      }
      final dc = dcFor(opt.type, ev.chapter);
      final r = _resolve(opt.type, dc);
      lastResult = r;
      lastOption = opt;
      int gd;
      int xd = 0;
      final newStats = Map<TribeStat, int>.of(_state.stats);
      int newScore = _state.creditScore;
      int cStreak = _state.cShortWinStreak;
      List<Equipment> bag = List.of(_state.bag);
      Map<EquipSlot, Equipment?> eq = Map.of(_state.equipped);
      if (r.outcome.isSuccess) {
        double mul = r.payoutMul;
        if (opt.type == ChoiceType.shortSale &&
            _state.titles.contains('ACH_001')) mul *= 1.05;
        if (opt.type == ChoiceType.shortSale && _hasHedgeClaw) mul *= 1.10;
        if (opt.type == ChoiceType.shortSale &&
            r.outcome == DiceOutcome.criticalSuccess &&
            _state.mythicEquipped) mul *= 1.20;
        // [유물] 황금 발톱: C형 성공 보상 +%
        if (opt.type == ChoiceType.shortSale) {
          mul *= 1 + relicSum(RelicFx.cGold);
        }
        // [유물] 복수의 송곳니: 컴백(직전 실패 후 성공) 보상 +%
        if (lastWasFail) mul *= 1 + relicSum(RelicFx.comeback);
        // [게임성] 연승 보너스 (+ [유물] 야성의 토템 가중)
        final int sb = _ci(successStreak, 0, Cfg.streakBonusCap);
        if (sb > 0) {
          final double per = Cfg.streakBonusPer + relicSum(RelicFx.streak).toDouble();
          mul *= 1 + sb * per;
          flashes.add('🔥 ${sb + 1}연승 보너스 +${(sb * per * 100).round()}%');
        }
        // [게임성] 가변 보상(변동비율) + 잭팟 (+ [유물] 도박꾼의 동전 확률↑)
        final bool jackpot =
            _random.nextDouble() < Cfg.jackpotChance + relicSum(RelicFx.jackpot);
        if (jackpot) {
          mul *= Cfg.jackpotMul;
        } else {
          mul *= Cfg.rewardVarMin +
              _random.nextDouble() * (Cfg.rewardVarMax - Cfg.rewardVarMin);
        }
        gd = (opt.goldSuccess * mul).round();
        if (jackpot) flashes.add('🎰 잭팟 대박!! 보상이 폭증했습니다!');
        xd = (opt.expSuccess * r.payoutMul).round();
        if (isHyperActive) xd = (xd * Cfg.hyperExpMul).round();
        narrative = opt.successText;
        final loot = _lootFrom(opt.itemReward);
        if (loot != null) {
          lastLoot = loot;
          if (loot.isMythicSuit) {
            if (!_state.mythicEquipped) {
              eq[EquipSlot.mythic] = loot;
              flashes.add('🎽 신화 「${loot.name}」 즉시 장착! ${loot.note}');
            }
          } else {
            bag.add(loot);
            flashes.add('🎁 전리품: [${loot.grade.label}] ${loot.name}');
          }
        }
        cStreak = opt.type == ChoiceType.shortSale ? cStreak + 1 : 0;
        // ── 연출 적정화: 전광판/흔들림은 '진짜 큰 순간'만 (juice 과용 방지) ──
        final wasComeback = lastWasFail;
        successStreak += 1;
        lastWasFail = false;
        final crit = r.outcome == DiceOutcome.criticalSuccess;
        if (wasComeback) {
          tinyLine = _pick(Tiny.comeback);
          critBanner = true;
          screenShake = true;
          critText = '🔥[오뚝이 부활]🔥 넘어졌던 맹수가 더 사납게 일어나 모든 걸 뒤집었습니다!';
        } else if (jackpot) {
          tinyLine = _pick(Tiny.jackpot);
          critBanner = true;
          screenShake = true;
          critText = '🎰[대박 잭팟]🎰 하늘이 대장님께 황금 비를 퍼붓습니다!!';
        } else if (crit) {
          tinyLine = Tiny.critical;
          critBanner = true;
          screenShake = true;
          critText = '⚡[대륙 속보]⚡ 대성공! 대장님이 단숨에 대부호의 반열에 올랐습니다!';
        } else if (opt.type == ChoiceType.transcend) {
          tinyLine = Tiny.success[ChoiceType.transcend]!;
          critBanner = true;
          screenShake = true;
          critText = '⚡[대륙 속보]⚡ 부족장님이 초월의 경지에 올라 의회를 무릎 꿇렸습니다!';
        } else if (successStreak >= 3) {
          tinyLine = _pick(Tiny.streak); // 일반 연승: 대사만, 전광판 X
        } else {
          tinyLine = Tiny.success[opt.type] ?? Tiny.success[ChoiceType.aggressive]!;
        }
      } else {
        gd = (opt.goldFail * r.payoutMul).round();
        opt.statFail.forEach((s, d) {
          newStats[s] = _ci((newStats[s] ?? 0) + d, 1, 99);
        });
        newScore += opt.creditFail * 50;
        narrative = opt.failText;
        if (opt.type == ChoiceType.shortSale) cStreak = 0;
        successStreak = 0;
        lastWasFail = true; // 다음 성공 시 컴백 환호 트리거
        // [게임성] 니어미스: 한 끗 차이 실패는 재도전 충동을 자극
        final miss = r.dc - r.finalValue;
        if (miss >= 1 && miss <= 2) {
          tinyLine = _pick(Tiny.nearMiss);
          flashes.add('🎯 한 끗 차이!! ($miss 부족) — 거의 이겼습니다!');
        } else {
          tinyLine = _pick(Tiny.failPool);
        }
        if (opt.isHiddenS && opt.sFailGameOver) {
          _state = _state.copyWith(
              stats: newStats, creditScore: newScore, gameOver: true);
          _stage = Stage.gameOver;
          return;
        }
      }
      final newGold = _clampGold(_state.bloodGold + gd);
      goldDelta = gd;
      expDelta = xd;
      _state = _state.copyWith(
        bloodGold: newGold,
        exp: _state.exp + xd,
        stats: newStats,
        creditScore: newScore,
        bag: bag,
        equipped: eq,
        raidLocked: newGold <= 0,
        cShortWinStreak: cStreak,
        totalEarned: _state.totalEarned + (gd > 0 ? gd : 0),
        completedEvents: {..._state.completedEvents, ev.id},
      );
      if (!_state.bankruptcyActive) {
        _state = _state.copyWith(creditGrade: gradeFromScore(_state.creditScore));
      }
      _checkAchievements();
      _applyLevelUp();
      _detectDomainEvolution();
      _unlockIfCleared(); // 무대 정복 시 해금+유물 보상을 결과 화면에서 바로 보여줌
      _stage = Stage.resolution;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // 결과 확인 → 턴 종료 → 다음 사건 자동 로드 (화면 이동 없음!)
  void next() {
    if (_busy || pendingStatChoices.isNotEmpty) return;
    if (_state.gameOver || _state.cleared) return;
    _busy = true;
    flashes.clear();
    try {
      _finishTurn();
      if (_state.gameOver) {
        _stage = Stage.gameOver;
        return;
      }
      _unlockIfCleared();
      if (pendingNews != null) {
        newsResolved = false;
        newsResolveText = '';
        _stage = Stage.news;
        return;
      }
      _loadNextStory();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _finishTurn() {
    final newTurn = _state.turn + 1;
    final cost = upkeep(newTurn);
    // [유물] 그림자 계약: 매 턴 시작 수입
    final int income = relicSum(RelicFx.income).toInt();
    final afterGold = _clampGold(_state.bloodGold - cost + income);
    if (income > 0) flashes.add('📜 유물 수입 +${fmt(income)}');
    final interest = _ci(_state.interestPenaltyTurns - 1, 0, 99);
    final acRelief = _ci(_state.acDcReliefTurns - 1, 0, 99);
    _state = _state.copyWith(
      turn: newTurn,
      bloodGold: afterGold,
      raidLocked: afterGold <= 0,
      interestPenaltyTurns: interest,
      acDcReliefTurns: acRelief,
    );
    flashes.add('🩸 유지비 -${fmt(cost)}');
    if (afterGold < 0) {
      _state = _state.copyWith(
        creditScore: _state.creditScore - Cfg.delinquencyCreditPenalty,
        delinquentStreak: _state.delinquentStreak + 1,
      );
      flashes.add('🩸 연체! 신용 -${Cfg.delinquencyCreditPenalty}');
      if (_state.delinquentStreak >= Cfg.marginCallStreak ||
          _state.creditGrade >= 4) _marginCall();
    } else {
      _state = _state.copyWith(delinquentStreak: 0);
    }
    if (!_state.bankruptcyActive) {
      _state = _state.copyWith(creditGrade: gradeFromScore(_state.creditScore));
    }
    _evaluateBankruptcy();
    if (_state.gameOver) return;
    _checkAchievements();
    // 돌발 뉴스 확률 ([유물] 의회의 밀서 보유 시 면역)
    double chance = Cfg.newsChance - (_hasSpyRing ? 0.05 : 0.0);
    if (relicSum(RelicFx.news) > 0) chance = 0;
    final eligible = kNews.where((n) => _state.turn >= n.minTurn).toList();
    if (eligible.isNotEmpty && chance > 0 && _random.nextDouble() < chance) {
      pendingNews = eligible[_random.nextInt(eligible.length)];
    }
  }

  void _unlockIfCleared() {
    final rid = currentRegion.id;
    if (_state.regionQuestsCleared(rid) && kUnlockChain.containsKey(rid)) {
      final next = kUnlockChain[rid]!;
      if (!_state.unlockedRegions.contains(next)) {
        _state = _state.copyWith(
            unlockedRegions: {..._state.unlockedRegions, next});
        flashes.add('🗺 새 지역 해금: ${kRegions[next]!.name}');
        grantRelic(); // 지역(무대) 정복 보상으로 유물 1개
        return;
      }
    }
  }

  void _detectDomainEvolution() {
    final now = _state.domainStage;
    if (now != domainShown) {
      domainShown = now;
      tinyLine = (now == '황금 제국' && _state.bloodGold >= 500000)
          ? Tiny.wealth
          : (Tiny.domain[now] ?? tinyLine);
      flashes.add('🏯 영지 진화 → $now!');
    }
  }

  // ===========================================================================
  //  사냥 (모달에서 호출 → 결과는 메인 화면)
  // ===========================================================================
  void hunt(HuntTarget t) {
    if (_busy || _state.gameOver || _state.cleared) return;
    _busy = true;
    flashes.clear();
    lastLoot = null;
    resultIsHunt = true;
    goldBefore = _state.bloodGold;
    critBanner = false;
    screenShake = false;
    _overlay = Overlay.none;
    try {
      final r = _resolve(_typeForStat(t.stat), t.dc);
      lastResult = r;
      lastHunt = t;
      int gd;
      int xd = 0;
      final newStats = Map<TribeStat, int>.of(_state.stats);
      if (r.outcome.isSuccess) {
        double hmul = r.payoutMul;
        // [유물] 황금 우상: 사냥 보상 +%  /  복수의 송곳니: 컴백 보상 +%
        hmul *= 1 + relicSum(RelicFx.huntGold);
        if (lastWasFail) hmul *= 1 + relicSum(RelicFx.comeback);
        final int sb = _ci(successStreak, 0, Cfg.streakBonusCap);
        if (sb > 0) {
          final double per = Cfg.streakBonusPer + relicSum(RelicFx.streak).toDouble();
          hmul *= 1 + sb * per;
          flashes.add('🔥 ${sb + 1}연승 보너스 +${(sb * per * 100).round()}%');
        }
        // [게임성] 가변 보상 + 잭팟 (+ [유물] 도박꾼의 동전)
        final bool jackpot =
            _random.nextDouble() < Cfg.jackpotChance + relicSum(RelicFx.jackpot);
        if (jackpot) {
          hmul *= Cfg.jackpotMul;
        } else {
          hmul *= Cfg.rewardVarMin +
              _random.nextDouble() * (Cfg.rewardVarMax - Cfg.rewardVarMin);
        }
        gd = (t.goldWin * hmul).round();
        if (jackpot) flashes.add('🎰 잭팟 대박!! 전리품이 폭증했습니다!');
        xd = (t.expWin * r.payoutMul).round();
        if (isHyperActive) xd = (xd * Cfg.hyperExpMul).round();
        narrative = '${t.name} 사냥 성공! 전리품을 약탈했습니다.';
        final wasComeback = lastWasFail;
        successStreak += 1;
        lastWasFail = false;
        final crit = r.outcome == DiceOutcome.criticalSuccess;
        if (wasComeback) {
          tinyLine = _pick(Tiny.comeback);
          critBanner = true;
          screenShake = true;
          critText = '🔥[오뚝이 부활]🔥 다친 발톱으로 더 큰 사냥감을 물어뜯었습니다!';
        } else if (jackpot) {
          tinyLine = _pick(Tiny.jackpot);
          critBanner = true;
          screenShake = true;
          critText = '🎰[대박 잭팟]🎰 사냥감 뱃속에서 황금이 쏟아집니다!!';
        } else if (crit) {
          tinyLine = Tiny.critical;
          critBanner = true;
          screenShake = true;
          critText = '⚡[대륙 속보]⚡ 부족장님의 사냥 한 방에 대륙이 진동합니다!';
        } else if (successStreak >= 3) {
          tinyLine = _pick(Tiny.streak);
        } else {
          tinyLine = Tiny.huntWin;
        }
      } else {
        gd = (t.goldLose * r.payoutMul).round();
        t.statLose.forEach((s, d) {
          newStats[s] = _ci((newStats[s] ?? 0) + d, 1, 99);
        });
        narrative = '${t.name}에게 반격당했습니다. 부상병 치료비가 나갑니다.';
        successStreak = 0;
        lastWasFail = true;
        final miss = r.dc - r.finalValue;
        if (miss >= 1 && miss <= 2) {
          tinyLine = _pick(Tiny.nearMiss);
          flashes.add('🎯 한 끗 차이!! ($miss 부족) — 거의 잡았습니다!');
        } else {
          tinyLine = _pick(Tiny.failPool);
        }
      }
      goldDelta = gd;
      expDelta = xd;
      final newGold = _clampGold(_state.bloodGold + gd);
      _state = _state.copyWith(
        bloodGold: newGold,
        exp: _state.exp + xd,
        stats: newStats,
        raidLocked: newGold <= 0,
        huntWins: _state.huntWins + (r.outcome.isSuccess ? 1 : 0),
        totalEarned: _state.totalEarned + (gd > 0 ? gd : 0),
      );
      _checkAchievements();
      _applyLevelUp();
      _detectDomainEvolution();
      _stage = Stage.resolution;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  //  상점
  // ===========================================================================
  int shopPriceOf(ShopItem item) {
    double mul = _state.creditGrade == 1
        ? 0.9
        : _state.creditGrade == 3
            ? 1.2
            : 1.0;
    return (item.price * mul).round();
  }

  bool canBuy(ShopItem item) {
    if (_state.creditGrade == 4) return false;
    if (_state.creditGrade > item.requiredGradeOrBetter) return false;
    return _state.bloodGold >= shopPriceOf(item);
  }

  void buy(ShopItem item) {
    if (_busy) return;
    _busy = true;
    try {
      if (_state.creditGrade == 4) {
        shopFlash = '⛔ 4등급(파산 임박) — 암시장 이용 봉쇄.';
        return;
      }
      if (_state.creditGrade > item.requiredGradeOrBetter) {
        shopFlash = '🔒 ${item.requiredGradeOrBetter}등급 이상 전용입니다.';
        return;
      }
      final price = shopPriceOf(item);
      if (_state.bloodGold < price) {
        shopFlash = '💸 마나 스톤 부족 (필요 ${fmt(price)})';
        return;
      }
      int newGold = _state.bloodGold - price;
      if (item.isCreditPotion) {
        int targetGrade = _ci(_state.creditGrade - 1, 2, 4);
        int newScore = _state.creditScore;
        if (targetGrade == 2 && newScore < 600) newScore = 600;
        if (targetGrade == 3 && newScore < 350) newScore = 350;
        _state = _state.copyWith(
            bloodGold: newGold, creditGrade: targetGrade, creditScore: newScore);
        shopFlash = '🧪 ${item.name} 사용 — 신용 $targetGrade등급 회복!';
      } else if (item.equipment != null) {
        _state = _state.copyWith(
            bloodGold: newGold, bag: [..._state.bag, item.equipment!]);
        shopFlash = '🛒 ${item.name} 구매! 캐릭터에서 장착하세요.';
      }
      _state = _state.copyWith(raidLocked: _state.bloodGold <= 0);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  //  장비 장착/해제
  // ===========================================================================
  void equip(Equipment e) {
    final bag = List<Equipment>.of(_state.bag);
    final eq = Map<EquipSlot, Equipment?>.of(_state.equipped);
    bag.remove(e);
    final prev = eq[e.slot];
    if (prev != null) bag.add(prev);
    eq[e.slot] = e;
    _state = _state.copyWith(bag: bag, equipped: eq);
    notifyListeners();
  }

  void unequip(EquipSlot slot) {
    final eq = Map<EquipSlot, Equipment?>.of(_state.equipped);
    final cur = eq[slot];
    if (cur == null) return;
    eq[slot] = null;
    _state = _state.copyWith(bag: [..._state.bag, cur], equipped: eq);
    notifyListeners();
  }

  void rest() {
    if (_busy || _state.gameOver || _state.cleared) return;
    _state = _state.copyWith(
        creditScore: _state.creditScore + Cfg.restCreditRecover);
    flashes.clear();
    flashes.add('🔥 정비 완료 — 신용 +${Cfg.restCreditRecover}');
    _overlay = Overlay.none;
    // 휴식도 1턴 소모
    _busy = true;
    try {
      _finishTurn();
      if (_state.gameOver) {
        _stage = Stage.gameOver;
        return;
      }
      _unlockIfCleared();
      if (pendingNews != null) {
        newsResolved = false;
        _stage = Stage.news;
        return;
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  //  돌발 뉴스
  // ===========================================================================
  void respondNews() {
    final n = pendingNews;
    if (n == null || newsResolved) return;
    _busy = true;
    try {
      if (n.respondStat == null) {
        _state = _state.copyWith(acDcReliefTurns: 2);
        newsResolveText = '🟢 ${n.successDesc}';
      } else {
        final r = _resolve(_typeForStat(n.respondStat!), n.respondDc);
        final defended = r.outcome.isSuccess;
        newsResolveText = defended
            ? '🟢 대응 성공 (${r.finalValue} vs DC ${n.respondDc}) — ${n.successDesc}'
            : '🔴 대응 실패 (${r.finalValue} vs DC ${n.respondDc}) — 악재 적중.';
        if (n.code == 'NS_002' && !defended) {
          final cut = (_state.bloodGold * 0.15).round();
          _state =
              _state.copyWith(bloodGold: _clampGold(_state.bloodGold - cut));
          newsResolveText += '  (마나 -${fmt(cut)})';
        }
        if (n.code == 'NS_003' && defended) {
          _state =
              _state.copyWith(bloodGold: _clampGold(_state.bloodGold + 10000));
        }
        if (n.code == 'NS_001') {
          _state = _state.copyWith(interestPenaltyTurns: 3);
        }
        if (n.respondStat == TribeStat.leather) {
          _state = _state.copyWith(
              newsLeatherDefenseStreak:
                  defended ? _state.newsLeatherDefenseStreak + 1 : 0);
        }
      }
      _checkAchievements();
      newsResolved = true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void dismissNews() {
    pendingNews = null;
    newsResolved = false;
    newsResolveText = '';
    flashes.clear();
    _loadNextStory();
    notifyListeners();
  }

  // ===========================================================================
  //  보스
  // ===========================================================================
  void _startBoss() {
    bossPhaseIndex = 0;
    bossLastResult = null;
    bossDone = false;
    bossNarrative = '의장 네오 맹수가 등판합니다. "감히 시스템의 주인을 거역하는가?"';
    _stage = Stage.boss;
  }

  void resolveBossPhase() {
    if (_busy || bossDone) return;
    _busy = true;
    try {
      final p = kBossPhases[bossPhaseIndex];
      final r = _resolve(_typeForStat(p.stat), p.dc);
      bossLastResult = r;
      if (r.outcome.isSuccess) {
        bossNarrative = '${p.name} 돌파! (${r.finalValue} vs DC ${p.dc})';
      } else {
        bossNarrative = '${p.name} 피격! (${r.finalValue} vs DC ${p.dc}) — ${p.penalty}';
        if (bossPhaseIndex == 0) {
          _state =
              _state.copyWith(bloodGold: _clampGold(_state.bloodGold - 20000));
        } else if (bossPhaseIndex == 1) {
          _state = _state.copyWith(creditGrade: _ci(_state.creditGrade + 2, 1, 4));
        } else {
          _destroyTopEquipment();
        }
      }
      bossPhaseIndex++;
      if (bossPhaseIndex >= kBossPhases.length) {
        bossDone = true;
        bossNarrative += '\n\n의장 네오 맹수를 끝내 밀어냈습니다! 최종 분기가 열립니다.';
        _state = _state.copyWith(
            exp: _state.exp + 500, titles: {..._state.titles, 'ACH_BOSS'});
        flashes.add('👑 진 보스 격파 — 칭호 「대륙의 절대 포식자」 획득.');
        tinyLine = Tiny.bossWin;
        _applyLevelUp();
        grantRelic(reason: '의장 네오 맹수의 심장에서'); // 보스 처치 보상 유물
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void proceedAfterBoss() {
    if (!bossDone) return;
    _setStory('SCR_012');
    notifyListeners();
  }

  // ===========================================================================
  //  레벨업 / 업적 / 위기
  // ===========================================================================
  void _applyLevelUp() {
    while (_state.level < Cfg.maxLevel) {
      final next = _state.level + 1;
      final req = Cfg.lvReqExp[next] ?? 1 << 30;
      if (_state.exp >= req) {
        _state = _state.copyWith(level: next);
        if (next == Cfg.maxLevel) {
          final ns = Map<TribeStat, int>.of(_state.stats);
          for (final s in TribeStat.values) {
            ns[s] = (ns[s] ?? 0) + 2;
          }
          _state = _state.copyWith(stats: ns);
          flashes.add('⬆ Lv.5 MAX! 모든 스탯 +2');
        } else {
          pendingStatChoices.add(next);
          flashes.add('⬆ Lv.$next! 스탯 보너스 선택');
        }
        tinyLine = Tiny.levelUp;
        if (next >= 2 && !_state.unlockedRegions.contains('arena')) {
          _state = _state.copyWith(
              unlockedRegions: {..._state.unlockedRegions, 'arena'});
          flashes.add('🗺 새 지역 해금: 피의 투기장');
        }
      } else {
        break;
      }
    }
  }

  void chooseStatBonus(TribeStat stat) {
    if (pendingStatChoices.isEmpty) return;
    final lv = pendingStatChoices.removeAt(0);
    final amount = lv == 4 ? 2 : 1;
    final ns = Map<TribeStat, int>.of(_state.stats);
    ns[stat] = (ns[stat] ?? 0) + amount;
    _state = _state.copyWith(stats: ns);
    notifyListeners();
  }

  void _checkAchievements() {
    final t = Set<String>.of(_state.titles);
    final before = t.length;
    if (_state.cShortWinStreak >= 3) t.add('ACH_001');
    if (_state.bloodGold >= 100000) t.add('ACH_003');
    if (_state.newsLeatherDefenseStreak >= 2) t.add('ACH_002');
    if (_state.creditGrade >= 4) t.add('ACH_004');
    if (t.length != before) {
      for (final code in t.difference(_state.titles)) {
        if (kTitles.containsKey(code)) {
          flashes.add('🏆 업적: ${kTitles[code]!.achName} → 「${kTitles[code]!.title}」');
        }
      }
      String active = _state.activeTitle;
      if (active.isEmpty && t.isNotEmpty) active = t.first;
      _state = _state.copyWith(titles: t, activeTitle: active);
    }
  }

  void setActiveTitle(String code) {
    if (!_state.titles.contains(code)) return;
    _state = _state.copyWith(activeTitle: code);
    notifyListeners();
  }

  void _marginCall() {
    final bag = List<Equipment>.of(_state.bag);
    final eq = Map<EquipSlot, Equipment?>.of(_state.equipped);
    Equipment? best;
    bool fromEq = false;
    EquipSlot? bestSlot;
    for (final e in bag) {
      if (best == null || e.grade.rank > best.grade.rank) best = e;
    }
    for (final entry in eq.entries) {
      final e = entry.value;
      if (e != null && (best == null || e.grade.rank > best.grade.rank)) {
        best = e;
        fromEq = true;
        bestSlot = entry.key;
      }
    }
    if (best == null) {
      flashes.add('⚠ 마진콜 — 압류할 장비 없음.');
      return;
    }
    if (fromEq && bestSlot != null) {
      eq[bestSlot] = null;
    } else {
      bag.remove(best);
    }
    _state = _state.copyWith(bag: bag, equipped: eq);
    flashes.add('🔗 마진콜 — [${best.grade.label}] ${best.name} 압류!');
  }

  void _destroyTopEquipment() {
    final bag = List<Equipment>.of(_state.bag);
    final eq = Map<EquipSlot, Equipment?>.of(_state.equipped);
    Equipment? best;
    EquipSlot? bestSlot;
    bool fromEq = false;
    for (final e in bag) {
      if (best == null || e.grade.rank > best.grade.rank) best = e;
    }
    for (final entry in eq.entries) {
      final e = entry.value;
      if (e != null && (best == null || e.grade.rank > best.grade.rank)) {
        best = e;
        fromEq = true;
        bestSlot = entry.key;
      }
    }
    if (best == null) return;
    if (fromEq && bestSlot != null) {
      eq[bestSlot] = null;
    } else {
      bag.remove(best);
    }
    _state = _state.copyWith(bag: bag, equipped: eq);
  }

  void _evaluateBankruptcy() {
    final gold = _state.bloodGold;
    if (!_state.bankruptcyActive && gold <= Cfg.bankruptcy) {
      _state = _state.copyWith(
        bankruptcyActive: true,
        creditGrade: Cfg.forcedGrade,
        graceRemaining: Cfg.graceTurns,
      );
      flashes.add('💀 파산 루틴! 신용 4등급 · 유예 ${Cfg.graceTurns}턴');
      tinyLine = Tiny.crisis;
    } else if (_state.bankruptcyActive) {
      if (gold > 0) {
        _state = _state.copyWith(bankruptcyActive: false, graceRemaining: 0);
        flashes.add('✅ 파산 탈출!');
      } else {
        final g = _state.graceRemaining - 1;
        if (g <= 0) {
          _state = _state.copyWith(graceRemaining: 0, gameOver: true);
        } else {
          _state = _state.copyWith(graceRemaining: g);
          flashes.add('⏳ 파산 유예 $g턴');
        }
      }
    }
  }

  // 오버레이 제어
  void openOverlay(Overlay o) {
    _overlay = o;
    shopFlash = '';
    notifyListeners();
  }

  void closeOverlay() {
    _overlay = Overlay.none;
    notifyListeners();
  }

  // 월드맵에서 지역 선택
  void travelTo(String regionId) {
    if (!_state.unlockedRegions.contains(regionId)) return;
    _overlay = Overlay.none;
    final r = kRegions[regionId]!;
    _state = _state.copyWith(currentRegion: regionId);
    if (r.hasShop) {
      _overlay = Overlay.shop;
    } else if (r.questEventIds.isNotEmpty &&
        _state.nextQuestOf(regionId) != null) {
      _loadNextStory();
    } else if (r.hunts.isNotEmpty) {
      _overlay = Overlay.hunt;
    } else if (r.isCamp) {
      tinyLine = Tiny.idle;
    }
    notifyListeners();
  }

  void reset() {
    // [게임성] 다회차 유산 — 직전 회차 결과로 영구 보너스 적립(패배해도 성장)
    if (_state.cleared) {
      metaStatBonus += Cfg.legacyStatClear;
      metaGoldBonus += Cfg.legacyGoldClear;
    } else if (_state.gameOver) {
      metaStatBonus += Cfg.legacyStatLose;
      metaGoldBonus += Cfg.legacyGoldLose;
    }
    _state = PlayerState.newGame();
    if (metaStatBonus > 0 || metaGoldBonus > 0) {
      final ns = Map<TribeStat, int>.of(_state.stats);
      for (final s in TribeStat.values) {
        ns[s] = (ns[s] ?? 0) + metaStatBonus;
      }
      _state = _state.copyWith(
          stats: ns, bloodGold: _state.bloodGold + metaGoldBonus);
      legacyNote =
          '🏵 야성의 유산 계승 — 시작 스탯 +$metaStatBonus · 금고 +${fmt(metaGoldBonus)}';
    } else {
      legacyNote = '';
    }
    _overlay = Overlay.none;
    activeEvent = null;
    lastResult = null;
    lastOption = null;
    narrative = '';
    goldDelta = 0;
    expDelta = 0;
    lastLoot = null;
    resultIsHunt = false;
    flashes.clear();
    pendingStatChoices.clear();
    goldBefore = 10000;
    tinyLine = Tiny.idle;
    critBanner = false;
    critText = '';
    screenShake = false;
    domainShown = '원시 부족';
    lastHunt = null;
    shopFlash = '';
    pendingNews = null;
    newsResolved = false;
    newsResolveText = '';
    bossPhaseIndex = 0;
    bossDone = false;
    bossLastResult = null;
    bossNarrative = '';
    freeRoam = false;
    playthrough += 1; // 회차 증가 → 2회차부터 가이드 해제
    lastWasFail = false;
    successStreak = 0;
    tinyFocus = false;
    // 같은 슬롯에서 새 회차 바로 시작(자동 저장 유지)
    beginAdventure();
  }

  static String fmt(int v) {
    final neg = v < 0;
    final s = v.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${neg ? '-' : ''}$b';
  }
}

// =============================================================================
//  [Juice] 타이프라이터 — 대사를 글자씩 출력(VN/RPG 표준). 다 나와야 진행 가능.
//   탭하면 즉시 전체 표시(스킵). onDone으로 '계속' 버튼 등장 신호.
// =============================================================================
class Typewriter extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback? onDone;
  const Typewriter(this.text, {super.key, required this.style, this.onDone});
  @override
  State<Typewriter> createState() => TypewriterState();
}

class TypewriterState extends State<Typewriter> {
  Timer? _t;
  int _n = 0;
  bool get done => _n >= widget.text.length;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant Typewriter old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _t?.cancel();
      _n = 0;
      _start();
    }
  }

  void _start() {
    _t = Timer.periodic(const Duration(milliseconds: 24), (timer) {
      if (_n >= widget.text.length) {
        timer.cancel();
        widget.onDone?.call();
        return;
      }
      setState(() => _n++);
      if (_n >= widget.text.length) {
        timer.cancel();
        widget.onDone?.call();
      }
    });
  }

  // 외부에서 호출: 타이핑 즉시 완료(스킵)
  void skip() {
    if (done) return;
    _t?.cancel();
    setState(() => _n = widget.text.length);
    widget.onDone?.call();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(widget.text.substring(0, _n), style: widget.style);
  }
}

// =============================================================================
//  [Juice] 타이니 포커스 게이트 — 아무데나 탭 폐지. 타이프라이터로 대사 출력 →
//   다 나오면 '계속 ▶' 버튼만으로 진행(무지성 연타 방지). 배경 탭은 스킵만.
// =============================================================================
class _TinyGate extends StatefulWidget {
  final String line;
  final VoidCallback onContinue;
  const _TinyGate({super.key, required this.line, required this.onContinue});
  @override
  State<_TinyGate> createState() => _TinyGateState();
}

class _TinyGateState extends State<_TinyGate> {
  final _tw = GlobalKey<TypewriterState>();
  bool _done = false;
  bool _btnReady = false;

  void _markDone() {
    if (_done) return;
    setState(() => _done = true);
    // 버튼 등장 직후 짧은 쿨다운 — 스킵 탭의 관성으로 바로 안 눌리게
    Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _btnReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // 배경 탭 = 타이핑 빨리보기(스킵)만. 진행은 아래 버튼으로만.
          if (!_done) _tw.currentState?.skip();
        },
        child: Container(
          color: Colors.black.withValues(alpha: 0.88),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 타이니 말풍선(타이프라이터)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A2114), Color(0xFF1A140C)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8A33D), width: 1.5),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                          colors: [Color(0xFF8A6A2C), Color(0xFF3A2F1C)]),
                      border: Border.all(color: const Color(0xFFE8A33D), width: 2),
                    ),
                    child: const Text('😼', style: TextStyle(fontSize: 28)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('타이니',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFE8A33D),
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Typewriter(
                        widget.line,
                        key: _tw,
                        onDone: _markDone,
                        style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.55,
                            color: Color(0xFFF3EBDF),
                            fontWeight: FontWeight.w500),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 22),
              // 진행은 '계속 ▶' 버튼으로만 (아무데나 탭 X)
              if (_done)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _btnReady ? 1 : 0.4,
                  child: ElevatedButton(
                    onPressed: _btnReady ? widget.onContinue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8A33D),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: const Color(0xFF6A5A2C),
                      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('다음 ▶',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                )
              else
                const Text('(화면을 탭하면 빨리 보기)',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9C8C7E))),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  [Juice] 재사용 연출 위젯
// =============================================================================
class DiceRoll extends StatefulWidget {
  final int finalRoll;
  final Color color;
  const DiceRoll({super.key, required this.finalRoll, this.color = const Color(0xFFE8A33D)});
  @override
  State<DiceRoll> createState() => _DiceRollState();
}

class _DiceRollState extends State<DiceRoll> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final _rng = Random();
  int _shown = 1;
  bool _settled = false;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
    _c.addListener(() {
      if (_c.value < 1.0) setState(() => _shown = 1 + _rng.nextInt(20));
    });
    _c.addStatusListener((st) {
      if (st == AnimationStatus.completed) {
        setState(() {
          _shown = widget.finalRoll;
          _settled = true;
        });
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _settled ? 1.0 : (0.85 + _c.value * 0.3);
    return Transform.rotate(
      angle: _settled ? 0 : _c.value * 12.566,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
                colors: [widget.color, widget.color.withValues(alpha: 0.55)]),
            boxShadow: [
              BoxShadow(
                  color: widget.color.withValues(alpha: _settled ? 0.6 : 0.3),
                  blurRadius: _settled ? 22 : 8,
                  spreadRadius: 1),
            ],
          ),
          child: Text('$_shown',
              style: const TextStyle(
                  fontSize: 38, fontWeight: FontWeight.bold, color: Colors.black)),
        ),
      ),
    );
  }
}

class CountUp extends StatelessWidget {
  final int from, to;
  final TextStyle style;
  final String prefix;
  const CountUp(
      {super.key, required this.from, required this.to, required this.style, this.prefix = ''});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: from.toDouble(), end: to.toDouble()),
      builder: (_, v, __) =>
          Text('$prefix${GameManager.fmt(v.round())}', style: style),
    );
  }
}

// 타이니 말풍선 — 큰 아바타 + 골드 강조 + 새 대사 시 팝/글로우(눈에 확 띄게)
class TinyBubble extends StatefulWidget {
  final String line;
  const TinyBubble(this.line, {super.key});
  @override
  State<TinyBubble> createState() => _TinyBubbleState();
}

class _TinyBubbleState extends State<TinyBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _c.forward();
  }

  @override
  void didUpdateWidget(covariant TinyBubble old) {
    super.didUpdateWidget(old);
    if (old.line != widget.line) _c.forward(from: 0); // 새 대사 → 팝+글로우
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
      builder: (_, child) {
        final glow = (1 - _c.value);
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 2, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFFE8A33D).withValues(alpha: 0.15 + glow * 0.5),
                  blurRadius: 10 + glow * 16,
                  spreadRadius: glow * 2),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A2114), Color(0xFF1A140C)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8A33D), width: 1.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF8A6A2C), Color(0xFF3A2F1C)]),
              border: Border.all(color: const Color(0xFFE8A33D), width: 2),
            ),
            child: const Text('😼', style: TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Text('타이니',
                    style: TextStyle(
                        fontSize: 12.5, color: Color(0xFFE8A33D), fontWeight: FontWeight.bold)),
                SizedBox(width: 5),
                Text('충직한 부관',
                    style: TextStyle(fontSize: 9.5, color: Color(0xFF9C8C7E))),
              ]),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(widget.line,
                    key: ValueKey(widget.line),
                    style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: Color(0xFFF3EBDF),
                        fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class CritBanner extends StatefulWidget {
  final String text;
  const CritBanner(this.text, {super.key});
  @override
  State<CritBanner> createState() => _CritBannerState();
}

class _CritBannerState extends State<CritBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      axisAlignment: -1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF7A5A1A), Color(0xFFE8A33D), Color(0xFF7A5A1A)]),
        ),
        child: Text(widget.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11.5, height: 1.3, fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }
}

class Shaker extends StatefulWidget {
  final Widget child;
  final bool shake;
  const Shaker({super.key, required this.child, required this.shake});
  @override
  State<Shaker> createState() => _ShakerState();
}

class _ShakerState extends State<Shaker> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    if (widget.shake) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant Shaker old) {
    super.didUpdateWidget(old);
    if (widget.shake && !old.shake) _c.forward(from: 0);
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
      builder: (_, child) {
        final dx = sin(_c.value * pi * 8) * 9 * (1 - _c.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

class GoldFlash extends StatefulWidget {
  const GoldFlash({super.key});
  @override
  State<GoldFlash> createState() => _GoldFlashState();
}

class _GoldFlashState extends State<GoldFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Opacity(
          opacity: (1 - _c.value) * 0.5,
          child: Container(color: const Color(0xFFFFD54F)),
        ),
      ),
    );
  }
}

class Pulse extends StatefulWidget {
  final Widget child;
  final Color glow;
  const Pulse({super.key, required this.child, this.glow = const Color(0xFFE8A33D)});
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
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
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: widget.glow.withValues(alpha: 0.25 + _c.value * 0.45),
                blurRadius: 8 + _c.value * 14,
                spreadRadius: _c.value * 2),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// =============================================================================
//  [UI 헬퍼]
// =============================================================================
class UI {
  static Widget badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color)),
        child: Text(text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      );

  static Widget bigBtn(String text, Color bg, Color fg, VoidCallback? onTap) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              disabledBackgroundColor: const Color(0xFF2A2018),
              padding: const EdgeInsets.symmetric(vertical: 15)),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      );

  static Widget chip(String label, String value, {Color? color}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9C8C7E))),
          const SizedBox(height: 1),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color ?? const Color(0xFFF0E6DC))),
        ],
      );

  static Widget expBar(PlayerState s) {
    final cur = Cfg.lvReqExp[s.level] ?? 0;
    final next = Cfg.lvReqExp[s.level + 1];
    final double ratio =
        next == null ? 1.0 : ((s.exp - cur) / (next - cur)).clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        tween: Tween(begin: 0, end: ratio),
        builder: (_, v, __) => LinearProgressIndicator(
          value: v,
          minHeight: 6,
          backgroundColor: const Color(0xFF2A2018),
          valueColor: const AlwaysStoppedAnimation(Color(0xFFE8A33D)),
        ),
      ),
    );
  }

  static String sign(int v) => v >= 0 ? '+$v' : '$v';
}

// =============================================================================
//  [View] 단일 게임 화면
// =============================================================================
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameManager m;

  // ── 결과 연출 게이팅: 연출이 끝나야 '다음 ▶' 활성 (무지성 연타 방지) ──
  bool _nextReady = false;
  Stage? _prevStage;
  String? _prevResultKey; // 같은 결과의 중복 타이머 방지
  Timer? _gateTimer;

  @override
  void initState() {
    super.initState();
    m = GameManager();
    m.addListener(_onChange);
    _prevStage = m.stage;
  }

  void _onChange() {
    // resolution 단계에 '새로' 진입하면 연출이 끝날 때까지 다음 버튼 잠금
    final key = '${m.stage}_${m.state.turn}_${m.goldDelta}_${m.resultIsHunt}';
    if (m.stage == Stage.resolution && key != _prevResultKey) {
      _prevResultKey = key;
      _nextReady = false;
      _gateTimer?.cancel();
      // 주사위(0.85s)+카운트업(1.1s) 연출을 충분히 본 뒤 활성
      _gateTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _nextReady = true);
      });
    }
    if (m.stage != Stage.resolution) {
      _prevResultKey = null;
    }
    _prevStage = m.stage;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gateTimer?.cancel();
    m.removeListener(_onChange);
    m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = m.stage;
    Widget content;
    // 풀스크린 단계
    if (stage == Stage.intro) {
      content = _intro();
    } else if (stage == Stage.ending) {
      content = _ending();
    } else if (stage == Stage.gameOver) {
      content = _gameOver();
    } else if (stage == Stage.boss) {
      content = _boss();
    } else if (stage == Stage.news) {
      content = _news();
    } else {
      content = _mainPlay(); // story / resolution 단일화면
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Stack(children: [
              content,
              // 아래에서 올라오는 모달
              if (m.overlay != Overlay.none) _modal(),
            ]),
          ),
        ),
      ),
    );
  }

  // ── 메인 플레이 (한 화면, 콘텐츠만 슬라이드) ──
  Widget _mainPlay() {
    final isResolution = m.stage == Stage.resolution;
    final crit = m.lastResult?.outcome == DiceOutcome.criticalSuccess;
    return Shaker(
      shake: m.screenShake && isResolution,
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _hud(),
          _sceneBand(),
          if (m.critBanner && isResolution) CritBanner(m.critText),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: isResolution
                  ? _resolutionCenter(key: const ValueKey('res'))
                  : _storyCenter(key: ValueKey('story_${m.activeEvent?.id}')),
            ),
          ),
          TinyBubble(m.tinyLine),
          isResolution ? _afterBar() : _choiceBar(),
        ]),
        if (crit && isResolution) const Positioned.fill(child: GoldFlash()),
        // 타이니 포커스 게이트: 사건 진입 시 화면 어둡게 + 타이니 단독 + 탭하여 진행
        if (m.tinyFocus && !isResolution) _tinyFocusGate(),
      ]),
    );
  }

  // ── 타이니 포커스 게이트 ──
  Widget _tinyFocusGate() {
    return _TinyGate(
      key: ValueKey('gate_${m.tinyLine}'),
      line: m.tinyLine,
      onContinue: m.dismissTinyFocus,
    );
  }

  // ── 상단 HUD ──
  Widget _hud() {
    final s = m.state;
    final gradeColor = s.creditGrade <= 1
        ? const Color(0xFF81C784)
        : s.creditGrade == 2
            ? const Color(0xFFE8C34A)
            : const Color(0xFFE57373);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      color: const Color(0xFF1A1410),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          UI.chip('턴', '${s.turn}'),
          UI.chip('🩸', GameManager.fmt(s.bloodGold),
              color: s.bloodGold <= 0 ? const Color(0xFFE57373) : null),
          UI.chip('신용', '${s.creditGrade}등급', color: gradeColor),
          UI.chip('Lv', '${s.level}'),
          UI.chip(m.isHyperActive ? '🚀' : '🔥', m.isHyperActive ? 'HW' : '야생'),
        ]),
        const SizedBox(height: 6),
        UI.expBar(s),
      ]),
    );
  }

  // ── 씬 배경 띠 + 액션 아이콘 ──
  Widget _sceneBand() {
    final r = m.currentRegion;
    final s = m.state;
    return Container(
      height: 74,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.centerLeft, end: Alignment.centerRight, colors: r.bg),
        border: Border(
            bottom: BorderSide(
                color: m.isHyperActive ? const Color(0xFFE8A33D) : const Color(0xFF3A2F28))),
      ),
      child: Row(children: [
        const SizedBox(width: 12),
        Text(r.emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Text('🏕 ${s.domainStage}${s.raidLocked ? " · ⛔약탈LOCK" : ""}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFFB8ADA2))),
              ]),
        ),
        _iconBtn('🗺', '월드맵', () => m.openOverlay(Overlay.worldMap)),
        _iconBtn('⚔', '사냥', () {
          if (m.currentRegion.hunts.isNotEmpty) {
            m.openOverlay(Overlay.hunt);
          } else {
            m.travelTo('arena');
          }
        }),
        _iconBtn('🏪', '상점', () => m.travelTo('market')),
        _iconBtn('🎒', '캐릭터', () => m.openOverlay(Overlay.character)),
        const SizedBox(width: 4),
      ]),
    );
  }

  Widget _iconBtn(String icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 1),
            Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFFD9CFC6))),
          ]),
        ),
      );

  // ── 중앙: 사건 지문 ──
  Widget _storyCenter({Key? key}) {
    if (m.freeRoam || m.activeEvent == null) {
      return SingleChildScrollView(
        key: key,
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const SizedBox(height: 20),
          const Text('🏆', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('대륙의 메인 정복을 모두 끝냈습니다!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('이제 자유롭게 사냥하고 영지를 불리며 대륙을 호령하십시오.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF9C8C7E), height: 1.6)),
        ]),
      );
    }
    final ev = m.activeEvent!;
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x22E8A33D),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(ev.chapter == 4 ? '종장' : '제${ev.chapter}장',
              style: const TextStyle(
                  color: Color(0xFFE8A33D), fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        Text(ev.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, height: 1.3)),
        const SizedBox(height: 16),
        Text(ev.mainText,
            style: const TextStyle(fontSize: 16, height: 1.85, color: Color(0xFFE0D6CB))),
      ]),
    );
  }

  // ── 중앙: 결과 연출 ──
  Widget _resolutionCenter({Key? key}) {
    final r = m.lastResult;
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (r != null) ...[
          DiceRoll(
              key: ValueKey('dice_${m.state.turn}_${r.rawRoll}_${m.goldDelta}'),
              finalRoll: r.rawRoll,
              color: r.outcome.color),
          const SizedBox(height: 10),
          UI.badge(r.outcome.label, r.outcome.color),
          const SizedBox(height: 6),
          Text(
              '원본 ${r.rawRoll} → 적용 ${r.effectiveRoll}'
              '${r.mythicApplied ? " (신화)" : ""}${r.hyperApplied ? " (고속도로)" : ""}'
              '  + 보정 ${UI.sign(r.statModifier + r.extraModifier)} = ${r.finalValue} vs DC ${r.dc}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9C8C7E))),
          const Divider(height: 20, color: Color(0xFF3A2F28)),
        ],
        Text(m.narrative,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, height: 1.7, color: Color(0xFFF0E6DC))),
        const SizedBox(height: 14),
        if (r != null) ...[
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            UI.badge(
                '${m.goldDelta >= 0 ? "🪙 +" : "🩸 "}${GameManager.fmt(m.goldDelta)}',
                m.goldDelta >= 0 ? const Color(0xFF4E7E4E) : const Color(0xFFB7402E)),
            if (m.expDelta > 0) UI.badge('✨ EXP +${m.expDelta}', const Color(0xFF9C7A3C)),
          ]),
          const SizedBox(height: 8),
          const Text('부족 금고', style: TextStyle(fontSize: 11, color: Color(0xFF9C8C7E))),
          CountUp(
            from: m.goldBefore,
            to: m.state.bloodGold,
            prefix: '🪙 ',
            style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: m.state.bloodGold < 0 ? const Color(0xFFE57373) : const Color(0xFFFFD54F)),
          ),
        ],
        const SizedBox(height: 12),
        if (m.flashes.isNotEmpty)
          Column(
              children: m.flashes
                  .map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(f,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFE8C34A))),
                      ))
                  .toList()),
      ]),
    );
  }

  // ── 하단: 선택지 ──
  Widget _choiceBar() {
    if (m.freeRoam || m.activeEvent == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF130F0C),
        child: Row(children: [
          Expanded(
              child: UI.bigBtn('⚔ 사냥', const Color(0xFFB7402E), Colors.white,
                  () => m.openOverlay(Overlay.hunt))),
          const SizedBox(width: 10),
          Expanded(
              child: UI.bigBtn('🗺 월드맵', const Color(0xFF4E4038), Colors.white,
                  () => m.openOverlay(Overlay.worldMap))),
        ]),
      );
    }
    final ev = m.activeEvent!;
    final s = m.state;
    final opts = ev.options.where((o) => !o.isHiddenS || s.sUnlocked).toList();
    // 1회차 추천 유형: 평소 A형, 약탈 봉쇄 시 B형
    final recType = s.raidLocked ? ChoiceType.conservative : ChoiceType.aggressive;
    return Container(
      padding: const EdgeInsets.all(10),
      color: const Color(0xFF130F0C),
      child: Column(
        children: opts.map((opt) {
          final ending = opt.isEnding;
          final hidden = opt.isHiddenS;
          final locked = s.raidLocked && opt.type == ChoiceType.aggressive && !ending;
          final chance = ending ? 0 : m.successChance(opt.type, m.dcFor(opt.type, ev.chapter));
          final recommend =
              m.tutorialActive && !ending && !hidden && opt.type == recType;
          final accent = hidden
              ? const Color(0xFFFFD54F)
              : ending
                  ? const Color(0xFF9D8DF1)
                  : recommend
                      ? const Color(0xFFE8A33D)
                      : const Color(0xFF4E4038);
          // 위험도 색상(성공확률): 초록(안전) / 노랑(보통) / 빨강(위험)
          final riskColor = chance >= 70
              ? const Color(0xFF81C784)
              : chance >= 40
                  ? const Color(0xFFE8C34A)
                  : const Color(0xFFE57373);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: locked ? null : () => m.choose(opt),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hidden
                      ? const Color(0xFF2A2410)
                      : ending
                          ? const Color(0xFF221A33)
                          : const Color(0xFF241B15),
                  foregroundColor: Colors.white,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  side: BorderSide(color: accent, width: recommend ? 2 : 1),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          hidden
                              ? '⭐ S형 · 초월 (히든)'
                              : ending
                                  ? '${opt.type.tag}형 · ${opt.endingTitle}'
                                  : '${recommend ? "⭐ " : ""}${opt.type.tag}형 · ${opt.type.concept}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: recommend ? const Color(0xFFFFD54F) : Colors.white)),
                    ),
                    if (!ending)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (locked ? const Color(0xFFE57373) : riskColor)
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: locked ? const Color(0xFFE57373) : riskColor),
                        ),
                        child: Text(locked ? '봉쇄' : '$chance%',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: locked ? const Color(0xFFE57373) : riskColor)),
                      ),
                  ]),
                  if (!ending) ...[
                    const SizedBox(height: 5),
                    Row(children: [
                      Text('DC ${m.dcFor(opt.type, ev.chapter)} · ${opt.type.stat.icon}${opt.type.stat.label}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9C8C7E))),
                      const Spacer(),
                      // 결과 미리보기 (성공 보상 / 실패 손실)
                      Text('성공 +${GameManager.fmt(opt.goldSuccess)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                      const Text('  /  ', style: TextStyle(fontSize: 11, color: Color(0xFF5C5048))),
                      Text(opt.goldFail == 0 ? '실패 손실 없음' : '실패 ${GameManager.fmt(opt.goldFail)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFE57373))),
                    ]),
                  ],
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 하단: 다음 / 레벨업 선택 ──
  Widget _afterBar() {
    if (m.pendingStatChoices.isNotEmpty) {
      final lv = m.pendingStatChoices.first;
      final amt = lv == 4 ? 2 : 1;
      return Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF130F0C),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('⬆ Lv.$lv 보너스 — 스탯 +$amt 선택',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE8A33D), fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: TribeStat.values
                .map((st) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton(
                          onPressed: () => m.chooseStatBonus(st),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF241B15),
                              side: const BorderSide(color: Color(0xFFE8A33D)),
                              padding: const EdgeInsets.symmetric(vertical: 12)),
                          child: Text('${st.icon}${st.label}', style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ]),
      );
    }
    // 연출(주사위·카운트업)이 끝나기 전엔 '다음 ▶' 잠금 → 무지성 연타 방지 + 보상 강제 노출
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF130F0C),
      child: _nextReady
          ? UI.bigBtn('다음 ▶', const Color(0xFFE8A33D), Colors.black, m.next)
          : Opacity(
              opacity: 0.5,
              child: UI.bigBtn('⏳ 결과 확인 중…', const Color(0xFF6A5A2C),
                  Colors.black, null),
            ),
    );
  }

  // ── 인트로 = 세이브 슬롯 선택 ──
  Widget _intro() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1E0A), Color(0xFF0E0B09)]),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(children: [
            const Text('🐯', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 4),
            const Text('PROJECT AUHHEUNG',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    color: Color(0xFFE8A33D))),
            const SizedBox(height: 3),
            const Text('야생 부족 맹수 정복기',
                style: TextStyle(fontSize: 12, color: Color(0xFF9C8C7E))),
            const SizedBox(height: 22),
            const Text('세이브 슬롯을 선택하세요',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFE8C34A))),
            const SizedBox(height: 12),
            for (int s = 1; s <= GameManager.slotCount; s++) _slotCard(s),
            const SizedBox(height: 12),
            const Text(
                '※ 다른 폰·브라우저에서 열면 저장이 자동으로 따로 관리됩니다.\n'
                '같은 기기에서 둘이 할 땐 서로 다른 슬롯을 쓰세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, height: 1.5, color: Color(0xFF7C6C5E))),
          ]),
        ),
      ),
    );
  }

  Widget _slotCard(int s) {
    final info = m.slotInfo(s);
    final empty = info == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1410),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: empty ? const Color(0xFF3A2F28) : const Color(0xFFE8A33D)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('슬롯 $s',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFE8A33D))),
            const Spacer(),
            if (!empty)
              Text(
                  info['clear'] == true
                      ? '🏆 클리어'
                      : info['over'] == true
                          ? '☠️ 소멸'
                          : '진행 중',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9C8C7E))),
          ]),
          const SizedBox(height: 8),
          if (empty)
            UI.bigBtn('＋ 새 게임 시작', const Color(0xFFE8A33D), Colors.black,
                () => m.newSlot(s))
          else ...[
            Text(
                '턴 ${info['turn']} · Lv.${info['lv']} · 🪙 ${GameManager.fmt(info['gold'] as int)}\n'
                '📍 ${info['region']}',
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: Color(0xFFD9CFC6))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: UI.bigBtn('▶ 이어하기', const Color(0xFFE8A33D), Colors.black,
                    () => m.loadSlot(s)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: ElevatedButton(
                  onPressed: () => _confirmDeleteSlot(s),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4E2A26),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15)),
                  child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  void _confirmDeleteSlot(int s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1410),
        title: Text('슬롯 $s 삭제',
            style: const TextStyle(color: Color(0xFFE57373), fontWeight: FontWeight.bold)),
        content: const Text('이 슬롯의 저장이 영구 삭제됩니다. 계속할까요?',
            style: TextStyle(color: Color(0xFFD9CFC6))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () {
              m.deleteSlot(s);
              Navigator.pop(ctx);
            },
            child: const Text('삭제', style: TextStyle(color: Color(0xFFE57373))),
          ),
        ],
      ),
    );
  }

  // ── 보스 ──
  Widget _boss() {
    final done = m.bossDone;
    final p = done ? null : kBossPhases[m.bossPhaseIndex];
    final r = m.bossLastResult;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF3A0F0C), Color(0xFF0E0B09)]),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🦁👁', style: TextStyle(fontSize: 54)),
        const SizedBox(height: 8),
        const Text('진 최종 보스 · 의장 네오 맹수',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFFE57373))),
        const SizedBox(height: 14),
        if (!done) ...[
          UI.badge('${m.bossPhaseIndex + 1} / ${kBossPhases.length} 페이즈', const Color(0xFF9C7A3C)),
          const SizedBox(height: 10),
          Text(p!.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          Text('요구: ${p.stat.label} / DC ${p.dc} · 패배 시 ${p.penalty}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9C8C7E))),
        ],
        const SizedBox(height: 16),
        Text(m.bossNarrative,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFFD9CFC6))),
        if (r != null && !done) ...[
          const SizedBox(height: 8),
          Text('🎲 ${r.rawRoll} → ${r.finalValue} vs DC ${r.dc} · ${r.outcome.label}',
              style: TextStyle(fontSize: 12, color: r.outcome.color)),
        ],
        const SizedBox(height: 22),
        done
            ? UI.bigBtn('최종 분기로 ▶', const Color(0xFFE8A33D), Colors.black, m.proceedAfterBoss)
            : UI.bigBtn('🎲 ${p!.stat.label} 판정', const Color(0xFFB7402E), Colors.white, m.resolveBossPhase),
      ]),
    );
  }

  // ── 돌발 뉴스 ──
  Widget _news() {
    final n = m.pendingNews!;
    return Container(
      color: const Color(0xFF160606),
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: const Color(0xFFB7402E),
          child: const Text('📢  대 륙  속 보  (BREAKING NEWS)',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
        ),
        const SizedBox(height: 22),
        Text(n.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFE8A33D))),
        const SizedBox(height: 12),
        Text(n.effectDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFFD9CFC6))),
        const SizedBox(height: 14),
        if (n.respondStat != null)
          UI.badge('대응 판정: ${n.respondStat!.label} / DC ${n.respondDc}', const Color(0xFF9C7A3C)),
        const SizedBox(height: 22),
        if (!m.newsResolved)
          UI.bigBtn(n.respondStat == null ? '버프 수령' : '🛡 대응 판정', const Color(0xFFB7402E), Colors.white, m.respondNews)
        else ...[
          Text(m.newsResolveText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFFF0E6DC))),
          const SizedBox(height: 18),
          UI.bigBtn('계속 ▶', const Color(0xFFE8A33D), Colors.black, m.dismissNews),
        ],
      ]),
    );
  }

  // ── 엔딩 ──
  Widget _ending() {
    final s = m.state;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1E0A), Color(0xFF0E0B09)]),
      ),
      padding: const EdgeInsets.all(26),
      child: SingleChildScrollView(
        child: Column(children: [
          const SizedBox(height: 16),
          Text(s.portrait, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 10),
          const Text('GAME CLEAR',
              style: TextStyle(
                  color: Color(0xFFE8A33D), fontSize: 25, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 14),
          Text(s.endingTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(m.narrative,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD9CFC6), fontSize: 14, height: 1.7)),
          const SizedBox(height: 14),
          UI.badge('🏆 ${s.endingAchievement}', const Color(0xFF9C7A3C)),
          const SizedBox(height: 10),
          Text(
              '최종 자산 ${GameManager.fmt(s.bloodGold)} · Lv.${s.level} · 칭호 ${s.titles.length}종 · 사냥 ${s.huntWins}승',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9C8C7E), fontSize: 12)),
          const SizedBox(height: 24),
          UI.bigBtn('새 회차 시작', const Color(0xFFE8A33D), Colors.black, m.reset),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  // ── 게임 오버 ──
  Widget _gameOver() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF3A0F0C), Color(0xFF0E0B09)]),
      ),
      padding: const EdgeInsets.all(26),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('☠️', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        const Text('부족 소멸',
            style: TextStyle(
                color: Color(0xFFE57373), fontSize: 25, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 14),
        const Text('금고를 끝내 복구하지 못했습니다.\n그림자 의회의 압류가 부족을 대륙에서 지웠습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFD9CFC6), fontSize: 14, height: 1.7)),
        const SizedBox(height: 24),
        UI.bigBtn('재기의 부족 창설', const Color(0xFFB7402E), Colors.white, m.reset),
      ]),
    );
  }

  // ── 모달 (아래에서 올라오는 시트) ──
  Widget _modal() {
    Widget body;
    String title;
    switch (m.overlay) {
      case Overlay.worldMap:
        title = '🗺 대륙 월드맵';
        body = _worldMapBody();
        break;
      case Overlay.shop:
        title = '🏪 암시장 뒷골목';
        body = _shopBody();
        break;
      case Overlay.hunt:
        title = '⚔ 사냥 / 약탈';
        body = _huntBody();
        break;
      case Overlay.character:
        title = '🎒 캐릭터 / 가방';
        body = _characterBody();
        break;
      case Overlay.none:
        return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: GestureDetector(
        onTap: m.closeOverlay,
        child: Container(
          color: Colors.black54,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Color(0xFF14100E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                border: Border(top: BorderSide(color: Color(0xFFE8A33D), width: 2)),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(children: [
                    Expanded(
                        child: Text(title,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                    IconButton(onPressed: m.closeOverlay, icon: const Icon(Icons.close)),
                  ]),
                ),
                Expanded(child: body),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _worldMapBody() {
    final s = m.state;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: kRegions.values.map((r) {
        final unlocked = s.unlockedRegions.contains(r.id);
        final here = s.currentRegion == r.id;
        final cleared = r.questEventIds.isNotEmpty && s.regionQuestsCleared(r.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: InkWell(
            onTap: unlocked ? () => m.travelTo(r.id) : null,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: unlocked ? r.bg : [const Color(0xFF15120F), const Color(0xFF0E0B09)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: here ? const Color(0xFFE8A33D) : const Color(0xFF3A2F28),
                    width: here ? 2 : 1),
              ),
              child: Row(children: [
                Text(unlocked ? r.emoji : '🔒', style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(unlocked ? r.name : '???',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      if (here) UI.badge('현위치', const Color(0xFFE8A33D)),
                      if (cleared) UI.badge('완료', const Color(0xFF4E7E4E)),
                    ]),
                    const SizedBox(height: 3),
                    Text(unlocked ? r.desc : '미지의 영역.',
                        style: const TextStyle(fontSize: 11, height: 1.35, color: Color(0xFFB8ADA2))),
                    const SizedBox(height: 4),
                    Wrap(spacing: 5, runSpacing: 4, children: [
                      if (r.questEventIds.isNotEmpty) UI.badge('📜 임무', const Color(0xFF9C7A3C)),
                      if (r.hunts.isNotEmpty) UI.badge('⚔ 사냥', const Color(0xFFB7402E)),
                      if (r.hasShop) UI.badge('🏪 상점', const Color(0xFF64B5F6)),
                      if (r.hasBoss) UI.badge('👑 보스', const Color(0xFFE57373)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _shopBody() {
    final s = m.state;
    return Column(children: [
      if (m.shopFlash.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Text(m.shopFlash, style: const TextStyle(fontSize: 12.5, color: Color(0xFFE8C34A))),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          const Text('신용 등급별 가격 변동',
              style: TextStyle(fontSize: 11, color: Color(0xFF9C8C7E))),
          const Spacer(),
          UI.badge(
              s.creditGrade == 1
                  ? '10% 할인'
                  : s.creditGrade == 3
                      ? '20% 할증'
                      : s.creditGrade == 4
                          ? '이용 불가'
                          : '정가',
              s.creditGrade == 1
                  ? const Color(0xFF81C784)
                  : s.creditGrade >= 3
                      ? const Color(0xFFE57373)
                      : const Color(0xFF9C8C7E)),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: kBlackMarket.map((item) {
            final price = m.shopPriceOf(item);
            final ok = m.canBuy(item);
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1410),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3A2F28)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(item.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                    Text('🪙 ${GameManager.fmt(price)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: ok ? const Color(0xFFE8A33D) : const Color(0xFF7C6C5E))),
                  ]),
                  const SizedBox(height: 4),
                  Text(item.effectDesc,
                      style: const TextStyle(fontSize: 11, height: 1.3, color: Color(0xFFB8ADA2))),
                  const SizedBox(height: 8),
                  Row(children: [
                    UI.badge(item.code == 'SHP_004' ? '제한 없음' : '${item.requiredGradeOrBetter}등급↑',
                        const Color(0xFF9C7A3C)),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: ok ? () => m.buy(item) : null,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8A33D),
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: const Color(0xFF2A2018),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7)),
                      child: const Text('구매', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _huntBody() {
    final r = m.currentRegion;
    if (r.hunts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('이 지역엔 사냥감이 없습니다.',
                style: TextStyle(color: Color(0xFF9C8C7E))),
            const SizedBox(height: 12),
            UI.bigBtn('⚔ 피의 투기장으로', const Color(0xFFB7402E), Colors.white,
                () => m.travelTo('arena')),
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: r.hunts.map((t) {
        final chance = m.successChance(m.typeForStat(t.stat), t.dc);
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1410),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3A2F28)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(t.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                Text('${t.stat.icon} DC ${t.dc}·$chance%',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9C8C7E))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                UI.badge('승 🪙+${GameManager.fmt(t.goldWin)}', const Color(0xFF4E7E4E)),
                const SizedBox(width: 6),
                UI.badge('패 🩸${GameManager.fmt(t.goldLose)}', const Color(0xFFB7402E)),
              ]),
              const SizedBox(height: 8),
              UI.bigBtn('사냥 개시 (턴 소모)', const Color(0xFFB7402E), Colors.white, () => m.hunt(t)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _characterBody() {
    final s = m.state;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF3E2F12), Color(0xFF1A1407)]),
              border: Border.all(color: const Color(0xFFE8A33D), width: 2),
            ),
            child: Text(s.portrait, style: const TextStyle(fontSize: 30)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('맹수 부족장 · Lv.${s.level}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text('${s.domainStage} · 누적 약탈 ${GameManager.fmt(s.totalEarned)} · 사냥 ${s.huntWins}승',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF9C8C7E))),
            ]),
          ),
        ]),
        const Divider(height: 22, color: Color(0xFF3A2F28)),
        const Text('스탯 (기본 + 장비)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...TribeStat.values.map((st) {
          final base = s.statOf(st);
          final eff = s.effectiveStat(st);
          final mod = GameManager.statModifierOf(eff);
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              SizedBox(width: 78, child: Text('${st.icon} ${st.label}', style: const TextStyle(fontSize: 12.5))),
              Text('$eff', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              if (eff != base)
                Text(' ($base+${eff - base})', style: const TextStyle(fontSize: 11, color: Color(0xFF81C784))),
              const Spacer(),
              Text('판정 ${UI.sign(mod)}', style: const TextStyle(fontSize: 12, color: Color(0xFF9C8C7E))),
            ]),
          );
        }),
        const Divider(height: 22, color: Color(0xFF3A2F28)),
        const Text('장착 슬롯', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...EquipSlot.values.map((slot) {
          final e = s.equipped[slot];
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: const Color(0xFF1A1410),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF3A2F28))),
              child: Row(children: [
                Text('${slot.icon} ${slot.label}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9C8C7E))),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e == null ? '— 비어있음 —' : '[${e.grade.label}] ${e.name}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: e == null ? const Color(0xFF7C6C5E) : e.grade.color)),
                ),
                if (e != null)
                  TextButton(onPressed: () => m.unequip(slot), child: const Text('해제', style: TextStyle(fontSize: 12))),
              ]),
            ),
          );
        }),
        const Divider(height: 22, color: Color(0xFF3A2F28)),
        const Text('가방 (탭하여 장착)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (s.bag.isEmpty)
          const Text('— 비어있음 —', style: TextStyle(fontSize: 12, color: Color(0xFF7C6C5E)))
        else
          ...s.bag.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: InkWell(
                  onTap: () => m.equip(e),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: e.grade.color)),
                    child: Row(children: [
                      Text(e.slot.icon, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('[${e.grade.label}] ${e.name}',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: e.grade.color)),
                          if (e.statBonus.isNotEmpty)
                            Text(e.statBonus.entries.map((x) => '${x.key.label} +${x.value}').join(' · '),
                                style: const TextStyle(fontSize: 11, color: Color(0xFF9C8C7E))),
                        ]),
                      ),
                      const Text('장착', style: TextStyle(fontSize: 12, color: Color(0xFFE8A33D))),
                    ]),
                  ),
                ),
              )),
        const Divider(height: 22, color: Color(0xFF3A2F28)),
        const Text('칭호 (탭하여 장착)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (s.titles.isEmpty)
          const Text('— 해금된 칭호 없음 —', style: TextStyle(fontSize: 12, color: Color(0xFF7C6C5E)))
        else
          ...s.titles.map((code) {
            final td = kTitles[code];
            if (td == null) return const SizedBox.shrink();
            final active = s.activeTitle == code;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: InkWell(
                onTap: () => m.setActiveTitle(code),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: active ? const Color(0x22E8A33D) : null,
                      border: Border.all(color: active ? const Color(0xFFE8A33D) : const Color(0xFF3A2F28))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${active ? "★ " : ""}${td.title} (${td.achName})',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    Text(td.effect, style: const TextStyle(fontSize: 10.5, color: Color(0xFF9C8C7E))),
                  ]),
                ),
              ),
            );
          }),
        const Divider(height: 22, color: Color(0xFF3A2F28)),
        Row(children: [
          const Text('유물 (전투 중 영구 효과)', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${s.relics.length} / ${kRelics.length}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9C8C7E))),
        ]),
        const SizedBox(height: 6),
        if (s.relics.isEmpty)
          const Text('— 아직 없음 · 무대를 정복하고 보스를 쓰러뜨려 약탈하세요 —',
              style: TextStyle(fontSize: 12, color: Color(0xFF7C6C5E)))
        else
          ...s.relics.map((id) {
            final rl = kRelics[id];
            if (rl == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0x22B07A2E),
                    border: Border.all(color: const Color(0xFFC9962E))),
                child: Row(children: [
                  Text(rl.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(rl.name,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE8C66A))),
                      Text(rl.desc,
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF9C8C7E))),
                    ]),
                  ),
                ]),
              ),
            );
          }),
        const Divider(height: 22, color: Color(0xFF3A2F28)),
        UI.bigBtn('🏠 슬롯 선택으로 (진행 자동 저장됨)', const Color(0xFF4E4038),
            Colors.white, m.toSlotMenu),
      ],
    );
  }
}
