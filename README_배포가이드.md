# 🐯 어흥 : 야수의 생존 — 배포 안내

뱀파이어 서바이버즈류 **Flutter Web 게임**. 이 폴더(`web_deploy`)가 곧 GitHub 저장소이자 Flutter 프로젝트입니다.

## ▶ 플레이 (라이브)
https://ppyojog.github.io/auh-heung/

## 🚀 업데이트(배포) 하는 법
상위 **어흥 폴더**의 **`업데이트.bat`** 더블클릭 → GitHub에 자동 업로드 → 2~4분 뒤 자동 빌드·배포.
(또는 터미널: `git add -A && git commit -m "update" && git push`)

## 📁 구조
- `lib/main.dart` — 게임 전체 코드 (단일 파일)
- `web/index.html` — 웹 진입점
- `pubspec.yaml` — Flutter 설정
- `.github/workflows/deploy.yml` — push 시 자동 빌드/배포 (GitHub Actions)
- `docs/` — 설계 문서
  - `GDD.md` — 설계·역사 (서술)
  - `AuhHeung_DB.xlsx` — 밸런스 수치 데이터 (엑셀)
  - `build_db.py` — 엑셀 생성기 (데이터 정본, `python build_db.py`로 재생성)

## ⚠ 빌드 제약
- Flutter **3.24.5** 고정 · 렌더러 `--web-renderer html`
- 색 투명도는 반드시 `color.withOpacity(x)` (`withValues` 쓰면 컴파일 실패)
